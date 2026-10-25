import { supabase } from './api.js'

// ===== Precios según el documento del proyecto (Tabla 1, FIN-01) =====
// OJO: aquí solo se usan para MOSTRAR el carrito. El valor real lo calcula el servidor
// (supabase/functions/crear-pago), así nadie puede alterar el precio desde el navegador.
export const PRECIO_SUSCRIPCION_MENSUAL = 450000 // COP por conjunto, por mes
export const CUOTA_INSTALACION = 2000000         // COP por conjunto nuevo, única vez
export const IVA = 0                              // debe coincidir con la Edge Function
export const MESES_PERMITIDOS = [1, 3, 6, 12]

const REF_KEY = 'comunify_ultimo_pago'

export function formatCOP(valor) {
  return new Intl.NumberFormat('es-CO', {
    style: 'currency',
    currency: 'COP',
    maximumFractionDigits: 0,
  }).format(valor)
}

// Arma el carrito: items, subtotal, IVA y total
export function calcularCarrito({ modo, meses }) {
  const items = []
  if (modo === 'alta') {
    items.push({
      id: 'instalacion',
      nombre: 'Cuota de instalación',
      detalle: 'Instalación, códigos QR y capacitación (pago único)',
      cantidad: 1,
      precio: CUOTA_INSTALACION,
    })
  }
  items.push({
    id: 'suscripcion',
    nombre: 'Suscripción mensual Comunify',
    detalle: `${meses} ${meses === 1 ? 'mes' : 'meses'} x ${formatCOP(PRECIO_SUSCRIPCION_MENSUAL)}`,
    cantidad: meses,
    precio: PRECIO_SUSCRIPCION_MENSUAL,
  })

  const subtotal = items.reduce((acc, it) => acc + it.cantidad * it.precio, 0)
  const iva = Math.round(subtotal * IVA)
  return { items, subtotal, iva, total: subtotal + iva }
}

// 'simulado' (demostración, sin dinero real) o 'wompi' (pasarela real)
export async function modoPagos() {
  try {
    const { data, error } = await supabase.rpc('modo_pagos')
    if (error || !data) return 'wompi'
    return data
  } catch {
    return 'wompi'
  }
}

function mensajeDeError(error) {
  return (error && error.message) || 'No se pudo completar la operación. Inténtalo de nuevo.'
}

// Prueba gratuita de 7 días
export async function iniciarPrueba(datos) {
  const { data, error } = await supabase.rpc('iniciar_prueba', {
    p_conjunto: datos.conjunto,
    p_nit: datos.nit,
    p_contacto: datos.contacto,
    p_email: datos.email,
    p_telefono: datos.telefono || null,
  })
  if (error) throw new Error(mensajeDeError(error))
  return data // { prueba_hasta }
}

// Crea el pago. En modo simulado va al simulador; en modo real, al Web Checkout de Wompi.
export async function iniciarPago(datos) {
  if ((await modoPagos()) === 'simulado') {
    const { data, error } = await supabase.rpc('crear_pago_simulado', {
      p_modo: datos.modo,
      p_meses: datos.meses,
      p_nit: datos.nit,
      p_email: datos.email,
      p_conjunto: datos.conjunto || null,
      p_contacto: datos.contacto || null,
      p_telefono: datos.telefono || null,
    })
    if (error) throw new Error(mensajeDeError(error))
    try { localStorage.setItem(REF_KEY, data.reference) } catch { /* opcional */ }
    window.location.href = `simulador-pago.html?ref=${data.reference}`
    return
  }

  const { data, error } = await supabase.functions.invoke('crear-pago', { body: datos })

  if (error) {
    let mensaje = 'No se pudo iniciar el pago. Inténtalo de nuevo.'
    try {
      const detalle = await error.context.json()
      if (detalle?.error) mensaje = detalle.error
    } catch { /* se deja el mensaje general */ }
    throw new Error(mensaje)
  }

  try { localStorage.setItem(REF_KEY, data.reference) } catch { /* opcional */ }
  window.location.href = data.checkoutUrl
}

// Simulador: aprobar, rechazar o fallar un pago pendiente
export async function simularPago(reference, resultado, metodo) {
  const { error } = await supabase.rpc('simular_pago', {
    p_reference: reference, p_resultado: resultado, p_metodo: metodo,
  })
  if (error) throw new Error(mensajeDeError(error))
}

// Busca la referencia del pago en la URL (o en el navegador si Wompi no la devolvió)
export function leerReferencia() {
  const m = window.location.search.match(/COM-\d+-[A-Z0-9]+/)
  if (m) return m[0]
  try { return localStorage.getItem(REF_KEY) } catch { return null }
}

export async function consultarPago(reference) {
  const { data, error } = await supabase.rpc('consultar_pago', { p_reference: reference })
  if (error) throw new Error(error.message)
  return data && data.length ? data[0] : null
}
