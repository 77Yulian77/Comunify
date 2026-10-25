// Edge Function: wompi-webhook
// Recibe el evento "transaction.updated" de Wompi, valida la firma (checksum SHA-256),
// comprueba el valor y actualiza el pago y la suscripción.
//
// Despliegue (Wompi no envía JWT de Supabase, por eso se desactiva la verificación):
//   supabase functions deploy wompi-webhook --no-verify-jwt
// URL de eventos en Wompi (Desarrolladores > URL de eventos):
//   https://<PROJECT_REF>.supabase.co/functions/v1/wompi-webhook
// Secreto necesario:  supabase secrets set WOMPI_EVENTS_SECRET=...

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

async function sha256Hex(text: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

// Lee un valor anidado: "transaction.id" -> data.transaction.id
function getByPath(obj: any, path: string) {
  return path.split('.').reduce((acc, key) => (acc == null ? undefined : acc[key]), obj)
}

function addMonths(date: Date, months: number) {
  const d = new Date(date)
  d.setMonth(d.getMonth() + months)
  return d
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 })

  try {
    const event = await req.json()
    const { data, signature, timestamp } = event

    if (!data || !signature?.properties || !signature?.checksum || timestamp == null) {
      return new Response('Evento inválido', { status: 400 })
    }

    // 1) Validar firma: valores de signature.properties (en orden) + timestamp + secreto de eventos
    const concatenated =
      signature.properties.map((p: string) => String(getByPath(data, p))).join('') +
      String(timestamp) +
      Deno.env.get('WOMPI_EVENTS_SECRET')
    const calculated = await sha256Hex(concatenated)
    if (calculated.toUpperCase() !== String(signature.checksum).toUpperCase()) {
      return new Response('Firma inválida', { status: 401 })
    }

    if (event.event !== 'transaction.updated') return new Response('ok', { status: 200 })

    const tx = data.transaction
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    const { data: pago } = await supabase.from('pagos').select('*').eq('reference', tx.reference).maybeSingle()
    if (!pago) return new Response('Referencia desconocida', { status: 200 }) // 200 para que Wompi no reintente

    // 2) El valor pagado debe coincidir con el calculado por el servidor
    if (Number(tx.amount_in_cents) !== Number(pago.total_cop) * 100) {
      console.error('Monto no coincide', tx.reference)
      await supabase.from('pagos').update({ estado: 'ERROR', updated_at: new Date().toISOString() }).eq('id', pago.id)
      return new Response('ok', { status: 200 })
    }

    const yaAprobado = pago.estado === 'APPROVED'
    const nuevoEstado = ['APPROVED', 'DECLINED', 'VOIDED', 'ERROR'].includes(tx.status) ? tx.status : 'PENDING'

    // Un pago ya aprobado no se modifica (evita activar dos veces si Wompi reenvía el evento)
    if (yaAprobado) return new Response('ok', { status: 200 })

    await supabase.from('pagos').update({
      estado: nuevoEstado,
      wompi_transaction_id: tx.id,
      metodo_pago: tx.payment_method_type ?? null,
      updated_at: new Date().toISOString(),
    }).eq('id', pago.id)

    // 3) Pago aprobado -> activar o renovar la suscripción
    if (nuevoEstado === 'APPROVED') {
      const { data: sus } = await supabase.from('suscripciones').select('*').eq('id', pago.suscripcion_id).single()
      const ahora = new Date()
      // Si todavía está vigente, la renovación suma meses desde el vencimiento; si no, desde hoy
      const base = sus.proximo_cobro && new Date(sus.proximo_cobro) > ahora ? new Date(sus.proximo_cobro) : ahora
      await supabase.from('suscripciones').update({
        estado: 'activa',
        inicio: sus.inicio ?? ahora.toISOString(),
        meses_pagados: sus.meses_pagados + pago.meses,
        proximo_cobro: addMonths(base, pago.meses).toISOString(),
      }).eq('id', sus.id)
    }

    return new Response('ok', { status: 200 })
  } catch (err) {
    console.error('wompi-webhook', err)
    return new Response('error', { status: 500 }) // Wompi reintenta si no recibe 200
  }
})
