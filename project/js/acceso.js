import { supabase } from './api.js'

// Consulta si la plataforma está habilitada (suscripción activa o prueba vigente).
// Si la consulta falla (por ejemplo, la migración aún no se aplicó) NO se bloquea el sitio.
export async function obtenerEstadoPlataforma() {
  try {
    const { data, error } = await supabase.rpc('estado_plataforma')
    if (error || !data) return { acceso: true, estado: 'desconocido' }
    return data
  } catch {
    return { acceso: true, estado: 'desconocido' }
  }
}

function mostrarBanner(dias) {
  if (document.getElementById('banner-prueba')) return
  const bar = document.createElement('div')
  bar.id = 'banner-prueba'
  bar.className = 'bg-amber-50 border-b border-amber-200 text-amber-800 text-sm px-4 py-2 text-center'
  bar.innerHTML = `Prueba gratuita: te ${dias === 1 ? 'queda 1 día' : `quedan ${dias} días`}. ` +
    '<a href="planes.html" class="font-semibold underline">Ver planes y suscribirme</a>'
  document.body.prepend(bar)
}

function mostrarBloqueo(estado) {
  if (document.getElementById('bloqueo-plataforma')) return
  const vencida = estado === 'vencida'
  const overlay = document.createElement('div')
  overlay.id = 'bloqueo-plataforma'
  overlay.setAttribute('role', 'dialog')
  overlay.className = 'fixed inset-0 z-[100] bg-gray-50 flex items-center justify-center p-4'
  overlay.innerHTML = `
    <div class="bg-white rounded-2xl border border-gray-200 shadow-lg max-w-md w-full p-8 text-center">
      <div class="w-14 h-14 rounded-full bg-amber-100 text-amber-600 mx-auto mb-4 flex items-center justify-center text-2xl">🔒</div>
      <h1 class="text-xl font-bold text-gray-900 mb-2">${vencida ? 'Tu prueba o suscripción terminó' : 'Esta plataforma requiere una suscripción'}</h1>
      <p class="text-gray-600 text-sm mb-6">${vencida
        ? '¿Quieres continuar usando Comunify? Puedes suscribirte ahora; tus reportes anteriores se conservan.'
        : 'Prueba Comunify gratis durante 7 días, sin tarjeta, o contrata un plan mensual.'}</p>
      <div class="flex flex-col gap-3">
        <a href="planes.html" class="bg-comunify-blue hover:bg-comunify-blue-dark text-white py-3 rounded-xl font-semibold text-sm">${vencida ? 'Suscribirme' : 'Ver planes y suscribirme'}</a>
        ${vencida ? '' : '<a href="planes.html#prueba" class="border border-comunify-blue text-comunify-blue hover:bg-comunify-blue/5 py-3 rounded-xl font-semibold text-sm">Probar 7 días gratis</a>'}
        <a href="index.html" class="text-gray-500 hover:text-gray-700 text-sm py-1">${vencida ? 'Ahora no, volver al inicio' : 'Volver al inicio'}</a>
      </div>
    </div>`
  document.body.appendChild(overlay)
  document.body.style.overflow = 'hidden'
}

// Llamar en cada página que solo debe verse con suscripción o prueba vigente.
export async function protegerPagina() {
  const estado = await obtenerEstadoPlataforma()
  if (!estado.acceso) mostrarBloqueo(estado.estado)
  else if (estado.estado === 'prueba') mostrarBanner(estado.dias_restantes)
  return estado
}
