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

  const { data: result, error } = await supabase
    .from('incidencias')
    .insert(payload)
    .select('ticket_number, created_at')
    .single()

  if (error) throw new Error(error.message)
  return result
}

export async function getIncidenciaByTicket(ticketNumber) {
  const { data, error } = await supabase
    .from('incidencias')
    .select('ticket_number, descripcion, torre, piso, zona, foto_url, estado, created_at')
    .eq('ticket_number', ticketNumber)
    .maybeSingle()

  if (error) throw new Error(error.message)
  return data
}

export async function getAllIncidencias(filters = {}) {
  let query = supabase
    .from('incidencias')
    .select('ticket_number, torre, piso, zona, estado, created_at, descripcion, foto_url')
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
  const { data, error } = await supabase
    .from('incidencias')
    .update({ estado: nuevoEstado })
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
