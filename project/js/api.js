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

// Saca la ruta del archivo dentro del bucket a partir de la URL pública de la foto
function getFotoPath(fotoUrl) {
  if (!fotoUrl) return null
  const marker = `/${STORAGE_BUCKET}/`
  const idx = fotoUrl.indexOf(marker)
  if (idx === -1) return null
  const path = fotoUrl.slice(idx + marker.length).split('?')[0]
  try {
    return decodeURIComponent(path) || null
  } catch {
    return path || null
  }
}

// Elimina tickets que estén en estado "Resuelto" (y sus fotos). Devuelve cuántos se eliminaron.
export async function deleteIncidenciasResueltas(incidencias) {
  const resueltas = (incidencias || []).filter((i) => i && i.estado === 'Resuelto')
  if (resueltas.length === 0) throw new Error('No hay tickets resueltos para eliminar')

  const tickets = resueltas.map((i) => i.ticket_number)
  const { data, error } = await supabase
    .from('incidencias')
    .delete()
    .in('ticket_number', tickets)
    .eq('estado', 'Resuelto')
    .select('ticket_number')

  if (error) throw new Error(error.message)
  if (!data || data.length === 0) {
    throw new Error('No se eliminó nada. Revisa que el ticket siga en estado Resuelto y vuelve a iniciar sesión.')
  }

  // Borra también las fotos de los tickets que sí se eliminaron (si falla, el ticket ya quedó eliminado)
  const borrados = new Set(data.map((d) => d.ticket_number))
  const paths = resueltas
    .filter((i) => borrados.has(i.ticket_number))
    .map((i) => getFotoPath(i.foto_url))
    .filter(Boolean)
  if (paths.length > 0) {
    try {
      await supabase.storage.from(STORAGE_BUCKET).remove(paths)
    } catch (err) {
      console.warn('No se pudieron borrar algunas fotos:', err)
    }
  }

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
  const { count: total, error: errTotal } = await supabase
    .from('incidencias')
    .select('*', { count: 'exact', head: true })

  const { count: pendientes, error: errP } = await supabase
    .from('incidencias')
    .select('*', { count: 'exact', head: true })
    .eq('estado', 'Pendiente')

  const { count: enProceso, error: errEP } = await supabase
    .from('incidencias')
    .select('*', { count: 'exact', head: true })
    .eq('estado', 'En Proceso')

  const { count: resueltos, error: errR } = await supabase
    .from('incidencias')
    .select('*', { count: 'exact', head: true })
    .eq('estado', 'Resuelto')

  if (errTotal || errP || errEP || errR) throw new Error('Error al obtener estadísticas')

  return {
    total: total || 0,
    pendientes: pendientes || 0,
    enProceso: enProceso || 0,
    resueltos: resueltos || 0,
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
