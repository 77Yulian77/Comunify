import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
})

const STORAGE_BUCKET = 'incidencia-fotos'

export async function createIncidencia(data) {
  if (!data.foto_url) throw new Error('La foto de evidencia es obligatoria')

  const payload = {
    descripcion: data.descripcion,
    torre: data.torre,
    piso: data.piso,
    zona: data.zona,
    foto_url: data.foto_url,
    residente_nombre: data.residente_nombre || null,
  }
  // Conjunto del enlace/QR; si no viene, la base lo deja en 'comunify'
  if (data.conjunto) payload.conjunto = data.conjunto

  const { data: result, error } = await supabase
    .from('incidencias')
    .insert(payload)
    .select('ticket_number, created_at')
    .single()

  if (error) throw new Error(error.message)
  return result
}

export async function getConjuntos() {
  const { data, error } = await supabase.from('conjuntos').select('slug, nombre').order('nombre')
  if (error) throw new Error(error.message)
  return data || []
}

export async function getIncidenciaByTicket(ticketNumber) {
  // consultar_ticket también encuentra los tickets eliminados con copia de respaldo,
  // para que el residente siga viendo su ticket aunque ya no esté en el panel
  const { data, error } = await supabase.rpc('consultar_ticket', { p_ticket: ticketNumber })
  if (!error) return (data && data[0]) || null

  // Si la función aún no existe en la base, se usa la consulta directa de antes
  const { data: directo, error: errDirecto } = await supabase
    .from('incidencias')
    .select('ticket_number, descripcion, torre, piso, zona, foto_url, estado, created_at, resolucion_comentario, resolucion_foto_url, resuelta_at')
    .eq('ticket_number', ticketNumber)
    .maybeSingle()

  if (errDirecto) throw new Error(errDirecto.message)
  return directo
}

export async function getAllIncidencias(filters = {}) {
  let query = supabase
    .from('incidencias')
    .select('ticket_number, torre, piso, zona, estado, created_at, descripcion, foto_url, resolucion_foto_url, conjunto')
    .order('created_at', { ascending: false })

  if (filters.torre && filters.torre !== 'all') {
    query = query.eq('torre', filters.torre)
  }
  if (filters.piso && filters.piso !== 'all') {
    query = query.eq('piso', parseInt(filters.piso))
  }
  if (filters.estado && filters.estado !== 'all') {
    query = query.eq('estado', filters.estado)
  }
  // El panel muestra los tickets activos; los archivados se ven en su pestaña
  query = query.eq('archivada', filters.archivadas === true)

  const { data, error } = await query
  if (error) throw new Error(error.message)
  return data
}

export async function updateIncidenciaEstado(ticketNumber, nuevoEstado) {
  // Si deja de estar Resuelto, se limpia la solución anterior
  const cambios = nuevoEstado === 'Resuelto'
    ? { estado: nuevoEstado }
    : { estado: nuevoEstado, resolucion_comentario: null, resolucion_foto_url: null, resuelta_at: null }
  const { data, error } = await supabase
    .from('incidencias')
    .update(cambios)
    .eq('ticket_number', ticketNumber)
    .select('ticket_number, estado')
    .single()

  if (error) throw new Error(error.message)
  return data
}

// Marca un ticket como Resuelto dejando comentario y foto de cómo quedó
export async function resolveIncidencia(ticketNumber, comentario, file) {
  const texto = (comentario || '').trim()
  if (texto.length < 5) throw new Error('Escribe un comentario de al menos 5 caracteres')
  if (texto.length > 500) throw new Error('El comentario no puede superar 500 caracteres')
  if (!file) throw new Error('La foto de la solución es obligatoria')
  if (!file.type.startsWith('image/')) throw new Error('El archivo debe ser una imagen')
  if (file.size > 10 * 1024 * 1024) throw new Error('La foto no puede superar 10 MB')

  const fotoUrl = await uploadFoto(file, `${ticketNumber}-resuelto-${Date.now()}`)

  const { data, error } = await supabase
    .from('incidencias')
    .update({
      estado: 'Resuelto',
      resolucion_comentario: texto,
      resolucion_foto_url: fotoUrl,
      resuelta_at: new Date().toISOString(),
    })
    .eq('ticket_number', ticketNumber)
    .select('ticket_number, estado')
    .single()

  if (error) throw new Error(error.message)
  return data
}

// Archiva tickets "Resuelto": salen del panel pero se conservan y se pueden consultar por su número.
export async function archiveIncidencias(incidencias) {
  const resueltas = (incidencias || []).filter((i) => i && i.estado === 'Resuelto')
  if (resueltas.length === 0) throw new Error('No hay tickets resueltos para archivar')

  const { data, error } = await supabase
    .from('incidencias')
    .update({ archivada: true, archivada_at: new Date().toISOString() })
    .in('ticket_number', resueltas.map((i) => i.ticket_number))
    .eq('estado', 'Resuelto')
    .select('ticket_number')

  if (error) throw new Error(error.message)
  if (!data || data.length === 0) {
    throw new Error('No se archivó nada. Revisa que el ticket siga en estado Resuelto y vuelve a iniciar sesión.')
  }
  return data.length
}

// Devuelve un ticket archivado al panel
export async function restoreIncidencia(ticketNumber) {
  const { data, error } = await supabase
    .from('incidencias')
    .update({ archivada: false, archivada_at: null })
    .eq('ticket_number', ticketNumber)
    .select('ticket_number')

  if (error) throw new Error(error.message)
  if (!data || data.length === 0) throw new Error('No se pudo restaurar el ticket')
  return data.length
}

// Elimina tickets. Con respaldo=true se guarda una copia (incidencias_respaldo) y se conservan las fotos;
// con respaldo=false se borran DEFINITIVAMENTE el ticket y sus fotos.
export async function deleteIncidencias(incidencias, { respaldo = false } = {}) {
  const lista = (incidencias || []).filter((i) => i && i.ticket_number)
  if (lista.length === 0) throw new Error('No hay tickets para eliminar')
  const tickets = lista.map((i) => i.ticket_number)

  if (respaldo) {
    const { data, error } = await supabase.rpc('eliminar_con_respaldo', { p_tickets: tickets })
    if (error) throw new Error(error.message)
    if (!data) throw new Error('No se eliminó nada. Ejecuta el SQL EJECUTAR_EN_SUPABASE.sql e inicia sesión de nuevo.')
    return data
  }

  const { data, error } = await supabase
    .from('incidencias')
    .delete()
    .in('ticket_number', tickets)
    .select('ticket_number')

  if (error) throw new Error(error.message)
  if (!data || data.length === 0) {
    throw new Error('No se eliminó nada. Ejecuta el SQL EJECUTAR_EN_SUPABASE.sql e inicia sesión de nuevo.')
  }

  const borrados = new Set(data.map((d) => d.ticket_number))
  const rutas = lista
    .filter((i) => borrados.has(i.ticket_number))
    .flatMap((i) => [rutaFoto(i.foto_url), rutaFoto(i.resolucion_foto_url)])
    .filter(Boolean)
  if (rutas.length > 0) {
    const { error: errFoto } = await supabase.storage.from(STORAGE_BUCKET).remove(rutas)
    if (errFoto) console.warn('Tickets eliminados, pero no se pudieron borrar algunas fotos:', errFoto.message)
  }
  return data.length
}

// ===== Respaldo (tickets eliminados con copia) =====
export async function getRespaldo() {
  const { data, error } = await supabase.rpc('listar_respaldo')
  if (error) throw new Error(error.message)
  return data || []
}

export async function restoreRespaldo(ticketNumber) {
  const { error } = await supabase.rpc('restaurar_respaldo', { p_ticket: ticketNumber })
  if (error) throw new Error(error.message)
}

// Borra del respaldo para siempre (y las fotos que guardaba)
export async function deleteRespaldo(items) {
  const lista = (items || []).filter((i) => i && i.ticket_number)
  if (lista.length === 0) throw new Error('No hay tickets para eliminar')
  const { data, error } = await supabase.rpc('borrar_de_respaldo', { p_tickets: lista.map((i) => i.ticket_number) })
  if (error) throw new Error(error.message)
  const rutas = lista.flatMap((i) => [rutaFoto(i.foto_url), rutaFoto(i.resolucion_foto_url)]).filter(Boolean)
  if (rutas.length > 0) {
    const { error: errFoto } = await supabase.storage.from(STORAGE_BUCKET).remove(rutas)
    if (errFoto) console.warn('Se borraron los tickets del respaldo, pero no algunas fotos:', errFoto.message)
  }
  return data
}

function rutaFoto(url) {
  if (!url) return null
  const marca = `/${STORAGE_BUCKET}/`
  const i = url.indexOf(marca)
  if (i === -1) return null
  return decodeURIComponent(url.slice(i + marca.length).split('?')[0])
}

export async function uploadFoto(file, ticketNumber) {
  const ext = file.name.split('.').pop().toLowerCase()
  const fileName = `${ticketNumber || Date.now()}.${ext}`
  const { data, error } = await supabase
    .storage
    .from(STORAGE_BUCKET)
    .upload(`incidencias/${fileName}`, file, {
      contentType: file.type,
      upsert: false,
    })

  if (error) throw new Error(error.message)

  const { data: urlData } = supabase
    .storage
    .from(STORAGE_BUCKET)
    .getPublicUrl(data.path)

  return urlData.publicUrl
}

export async function getIncidenciaStats() {
  const contar = (estado, archivada = false) => {
    let q = supabase.from('incidencias').select('*', { count: 'exact', head: true }).eq('archivada', archivada)
    if (estado) q = q.eq('estado', estado)
    return q
  }

  const [t, p, ep, r, a] = await Promise.all([
    contar(null), contar('Pendiente'), contar('En Proceso'), contar('Resuelto'), contar(null, true),
  ])

  if (t.error || p.error || ep.error || r.error || a.error) throw new Error('Error al obtener estadísticas')

  return {
    total: t.count || 0,
    pendientes: p.count || 0,
    enProceso: ep.count || 0,
    resueltos: r.count || 0,
    archivados: a.count || 0,
  }
}

export function sanitizeText(text) {
  if (!text) return ''
  const div = document.createElement('div')
  div.textContent = text.trim()
  return div.innerHTML
}

export const ZONAS = ['pasillo', 'parqueadero', 'ascensor', 'zonas_verdes', 'lobby']
export const TORRES = ['A', 'B', 'C']
export const PISOS = Array.from({ length: 17 }, (_, i) => i + 1)
export const ESTADOS = ['Pendiente', 'En Proceso', 'Resuelto']

export const ZONA_LABELS = {
  pasillo: 'Pasillo',
  parqueadero: 'Parqueadero',
  ascensor: 'Ascensor',
  zonas_verdes: 'Zonas Verdes',
  lobby: 'Lobby',
}

export const ESTADO_COLORS = {
  'Pendiente': { bg: '#fef3c7', text: '#92400e', dot: '#f59e0b' },
  'En Proceso': { bg: '#dbeafe', text: '#1e40af', dot: '#3b82f6' },
  'Resuelto': { bg: '#d1fae5', text: '#065f46', dot: '#10b981' },
}
