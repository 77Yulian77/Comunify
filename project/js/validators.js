export const DESCRIPCION_MIN = 10
export const FOTO_MAX_MB = 5

// Verifica que la descripción sea coherente con una incidencia real
// (texto con sentido, no teclazos al azar ni caracteres repetidos).
export function isDescripcionCoherente(texto) {
  const t = (texto || '').trim()
  const palabras = t.split(/\s+/).filter(Boolean)
  const letras = (t.match(/[a-záéíóúüñ]/gi) || []).length

  if (palabras.length < 2) return false                      // al menos 2 palabras
  if (letras < t.replace(/\s/g, '').length * 0.6) return false // mayoría letras (no solo números/símbolos)
  if (/(.)\1{3,}/i.test(t)) return false                     // "aaaa", "!!!!"
  if (new Set(palabras.map(p => p.toLowerCase())).size === 1) return false // misma palabra repetida
  const sinVocales = palabras.filter(p => p.length >= 4 && !/[aeiouáéíóúü]/i.test(p))
  if (sinVocales.length > 0) return false                    // "asdf", "qwrt"
  return true
}

export function validateIncidencia(data) {
  const errors = {}

  if (!data.descripcion || data.descripcion.trim().length < DESCRIPCION_MIN) {
    errors.descripcion = `La descripción debe tener al menos ${DESCRIPCION_MIN} caracteres para que la solicitud sea aceptada`
  } else if (!isDescripcionCoherente(data.descripcion)) {
    errors.descripcion = 'La descripción debe ser coherente con la incidencia que estás reportando'
  }

  if (!data.torre || !['A', 'B', 'C'].includes(data.torre)) {
    errors.torre = 'Selecciona una torre válida'
  }

  if (!data.piso || data.piso < 1 || data.piso > 17) {
    errors.piso = 'Selecciona un piso válido (1-17)'
  }

  if (!data.zona || !['pasillo', 'parqueadero', 'ascensor', 'zonas_verdes', 'lobby'].includes(data.zona)) {
    errors.zona = 'Selecciona una zona válida'
  }

  return errors
}

export function validateImageFile(file) {
  const errors = []
  const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png']
  const maxSize = FOTO_MAX_MB * 1024 * 1024

  if (!allowedTypes.includes(file.type)) {
    errors.push('Solo se permiten archivos JPG o PNG')
  }

  if (file.size > maxSize) {
    errors.push(`La foto no puede superar ${FOTO_MAX_MB} MB para ser aceptada`)
  }

  return errors
}

export function validateTicketNumber(ticket) {
  const pattern = /^TCK-\d{4}-\d{3}$/
  if (!ticket || !pattern.test(ticket.trim())) {
    return 'Formato de ticket inválido (ej: TCK-2026-001)'
  }
  return null
}

export function validateLogin(email, password) {
  const errors = {}
  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

  if (!email || !emailPattern.test(email)) {
    errors.email = 'Ingresa un correo electrónico válido'
  }

  if (!password || password.length < 6) {
    errors.password = 'La contraseña debe tener al menos 6 caracteres'
  }

  return errors
}

export function sanitizeInput(text) {
  if (!text) return ''
  return text.trim().replace(/[<>]/g, '')
}
