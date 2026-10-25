// Edge Function: crear-pago
// Calcula el valor en el SERVIDOR (nunca se confía en el valor que manda el navegador),
// registra la suscripción y el pago en estado PENDING y devuelve la URL del Web Checkout de Wompi.
//
// Variables de entorno (supabase secrets set ...):
//   WOMPI_PUBLIC_KEY        pub_test_xxx (pruebas) o pub_prod_xxx (producción)
//   WOMPI_INTEGRITY_SECRET  secreto de integridad (Wompi > Desarrolladores > Secretos)
//   SITE_URL                https://tu-sitio.netlify.app  (sin "/" al final)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las provee Supabase automáticamente.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ===== Precios según el documento del proyecto (Tabla 1, FIN-01) =====
const PRECIO_SUSCRIPCION_MENSUAL = 450_000 // COP por conjunto, por mes
const CUOTA_INSTALACION = 2_000_000        // COP por conjunto nuevo, una sola vez
const IVA = 0                              // el documento no discrimina IVA; cambiar a 0.19 si se factura con IVA
const MESES_PERMITIDOS = [1, 3, 6, 12]

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

async function sha256Hex(text: string) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

const clean = (v: unknown, max: number) => String(v ?? '').replace(/[<>]/g, '').trim().slice(0, max)

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  try {
    const body = await req.json()
    const modo = body.modo === 'renovacion' ? 'renovacion' : 'alta'
    const meses = Number(body.meses)
    const nit = clean(body.nit, 20).replace(/[^0-9A-Za-z-]/g, '')
    const email = clean(body.email, 120).toLowerCase()

    if (!MESES_PERMITIDOS.includes(meses)) return json({ error: 'Cantidad de meses no válida' }, 400)
    if (nit.length < 5) return json({ error: 'El NIT no es válido' }, 400)
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'El correo no es válido' }, 400)

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    let suscripcion: { id: string; conjunto_nombre: string; contacto_nombre: string } | null = null
    let incluyeInstalacion = false

    if (modo === 'renovacion') {
      // Cliente existente: se identifica con NIT + correo registrados
      const { data } = await supabase
        .from('suscripciones')
        .select('id, conjunto_nombre, contacto_nombre, estado, email')
        .eq('nit', nit)
        .maybeSingle()
      if (!data || data.email !== email || data.estado === 'pendiente' || data.estado === 'cancelada') {
        return json({ error: 'No encontramos una suscripción con ese NIT y correo' }, 404)
      }
      suscripcion = data
    } else {
      const conjunto = clean(body.conjunto, 120)
      const contacto = clean(body.contacto, 100)
      const telefono = clean(body.telefono, 20)
      if (conjunto.length < 3) return json({ error: 'Escribe el nombre del conjunto' }, 400)
      if (contacto.length < 3) return json({ error: 'Escribe el nombre del contacto' }, 400)

      const { data: existente } = await supabase
        .from('suscripciones').select('id, conjunto_nombre, contacto_nombre, estado').eq('nit', nit).maybeSingle()

      if (existente && !['pendiente', 'prueba'].includes(existente.estado)) {
        return json({ error: 'Este NIT ya tiene una suscripción. Usa la opción "Ya soy cliente".' }, 409)
      }
      if (existente) {
        suscripcion = existente
      } else {
        const { data: nueva, error } = await supabase
          .from('suscripciones')
          .insert({ conjunto_nombre: conjunto, nit, contacto_nombre: contacto, email, telefono: telefono || null })
          .select('id, conjunto_nombre, contacto_nombre')
          .single()
        if (error) throw error
        suscripcion = nueva
      }
      incluyeInstalacion = true // cuota de instalación solo en la primera compra
    }

    // ===== Cálculo del valor (servidor) =====
    const subtotal = PRECIO_SUSCRIPCION_MENSUAL * meses + (incluyeInstalacion ? CUOTA_INSTALACION : 0)
    const iva = Math.round(subtotal * IVA)
    const total = subtotal + iva
    const amountInCents = total * 100

    const reference = `COM-${Date.now()}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`

    const { error: errPago } = await supabase.from('pagos').insert({
      reference,
      suscripcion_id: suscripcion!.id,
      tipo: modo,
      meses,
      incluye_instalacion: incluyeInstalacion,
      subtotal_cop: subtotal,
      iva_cop: iva,
      total_cop: total,
    })
    if (errPago) throw errPago

    // ===== Firma de integridad (Wompi): SHA256(reference + amountInCents + currency + secret) =====
    const signature = await sha256Hex(`${reference}${amountInCents}COP${Deno.env.get('WOMPI_INTEGRITY_SECRET')}`)

    const siteUrl = (Deno.env.get('SITE_URL') ?? '').replace(/\/$/, '')
    const params = new URLSearchParams({
      'public-key': Deno.env.get('WOMPI_PUBLIC_KEY')!,
      currency: 'COP',
      'amount-in-cents': String(amountInCents),
      reference,
      'signature:integrity': signature,
      'redirect-url': `${siteUrl}/pago-resultado.html?ref=${reference}`,
      'customer-data:email': email,
      'customer-data:full-name': suscripcion!.contacto_nombre,
      'customer-data:legal-id': nit,
      'customer-data:legal-id-type': 'NIT',
    })

    return json({ reference, total, checkoutUrl: `https://checkout.wompi.co/p/?${params.toString()}` })
  } catch (err) {
    console.error('crear-pago', err)
    return json({ error: 'No se pudo iniciar el pago. Inténtalo de nuevo.' }, 500)
  }
})
