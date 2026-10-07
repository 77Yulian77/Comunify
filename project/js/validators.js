export function validateIncidencia(data) {
  const errors = {}

  if (!data.descripcion || data.descripcion.trim().length < 10) {
    errors.descripcion = 'La descripción debe tener al menos 10 caracteres'
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
  const maxSize = 5 * 1024 * 1024

  if (!allowedTypes.includes(file.type)) {
    errors.push('Solo se permiten archivos JPG o PNG')
  }

  if (file.size > maxSize) {
    errors.push('El archivo no debe superar 5MB')
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
