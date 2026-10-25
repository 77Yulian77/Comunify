// Edge Function: notificar-contacto
// Envía por correo las solicitudes de "Regístrate y nosotros te contactamos":
//   1) un aviso al correo del equipo (CONTACT_EMAIL) con los datos de la solicitud;
//   2) una confirmación a quien se registró (si el remitente lo permite).
// La solicitud YA quedó guardada en la base de datos antes de llamar esta función;
// si el correo no está configurado, no se pierde nada: se ve en la página "Solicitudes" del administrador.
//
// Secretos (supabase secrets set ...):
//   RESEND_API_KEY   llave de https://resend.com (plan gratuito)
//   CONTACT_EMAIL    correo del equipo que recibe las solicitudes
//   MAIL_FROM        opcional. Por defecto "Comunify <onboarding@resend.dev>" (solo para pruebas:
//                    Resend solo entrega a tu propio correo hasta que verifiques un dominio)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

const esc = (v: unknown) =>
  String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

async function enviar(key: string, payload: Record<string, unknown>) {
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  return r.ok
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const { id } = await req.json()
    if (!/^[0-9a-f-]{36}$/i.test(String(id))) return json({ ok: false }, 400)

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { data: sol } = await supabase.from('solicitudes_contacto').select('*').eq('id', id).maybeSingle()

    // Solo solicitudes recientes y aún no notificadas (evita usar la función para reenviar correos)
    if (!sol || sol.notificada || Date.now() - new Date(sol.created_at).getTime() > 15 * 60 * 1000) {
      return json({ ok: false, motivo: 'solicitud no válida para notificar' })
    }

    const key = Deno.env.get('RESEND_API_KEY')
    const equipo = Deno.env.get('CONTACT_EMAIL')
    if (!key || !equipo) return json({ ok: false, motivo: 'correo no configurado' })

    const from = Deno.env.get('MAIL_FROM') ?? 'Comunify <onboarding@resend.dev>'

    const aviso = await enviar(key, {
      from,
      to: [equipo],
      reply_to: sol.email,
      subject: `Nueva solicitud de contacto: ${sol.conjunto_nombre}`,
      html: `<h2>Nueva solicitud desde la página de Comunify</h2>
        <p><strong>Conjunto:</strong> ${esc(sol.conjunto_nombre)}</p>
        <p><strong>Contacto:</strong> ${esc(sol.contacto_nombre)}</p>
        <p><strong>Correo:</strong> ${esc(sol.email)}</p>
        <p><strong>Teléfono:</strong> ${esc(sol.telefono) || 'No indicó'}</p>
        <p><strong>Mensaje:</strong> ${esc(sol.mensaje) || 'Sin mensaje'}</p>
        <p style="color:#6b7280;font-size:12px">Puedes responder directamente a este correo.</p>`,
    })

    if (aviso) await supabase.from('solicitudes_contacto').update({ notificada: true }).eq('id', sol.id)

    // Confirmación a la persona (puede fallar con el remitente de pruebas; no es crítico)
    const confirmacion = await enviar(key, {
      from,
      to: [sol.email],
      subject: 'Recibimos tu solicitud - Comunify',
      html: `<p>Hola ${esc(sol.contacto_nombre)},</p>
        <p>Recibimos la solicitud de <strong>${esc(sol.conjunto_nombre)}</strong>. Te contactaremos muy pronto a este correo.</p>
        <p>Mientras tanto, puedes probar Comunify gratis durante 7 días desde nuestra página.</p>
        <p>Equipo Comunify</p>`,
    }).catch(() => false)

    return json({ ok: aviso, confirmacion })
  } catch (err) {
    console.error('notificar-contacto', err)
    return json({ ok: false }, 500)
  }
})
