import { supabase } from './api.js'

// Guarda la solicitud y, si el servicio de correo está configurado, avisa al equipo por correo.
// La solicitud queda guardada aunque el correo falle.
export async function enviarSolicitud({ conjunto, contacto, email, telefono, mensaje }) {
  const { data: id, error } = await supabase.rpc('registrar_solicitud_contacto', {
    p_conjunto: conjunto,
    p_contacto: contacto,
    p_email: email,
    p_telefono: telefono || null,
    p_mensaje: mensaje || null,
  })
  if (error) throw new Error(error.message)

  let correo = false
  try {
    const { data } = await supabase.functions.invoke('notificar-contacto', { body: { id } })
    correo = Boolean(data?.ok)
  } catch { /* el correo es opcional */ }

  return { id, correo }
}
