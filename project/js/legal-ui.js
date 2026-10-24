import { LEGAL } from './legal-info.js'

const COOKIE_KEY = 'comunify_aviso_cookies'

function fillLegalData() {
  document.querySelectorAll('[data-legal]').forEach((el) => {
    const key = el.dataset.legal
    if (key === 'direccion') el.textContent = LEGAL.direccion
    else if (key === 'correo') el.textContent = LEGAL.correo
    else if (key === 'version') el.textContent = LEGAL.version
    else if (key === 'correo-link') {
      el.textContent = LEGAL.correo
      el.setAttribute('href', `mailto:${LEGAL.correo}`)
    }
  })
}

function alreadyAccepted() {
  try {
    return localStorage.getItem(COOKIE_KEY) === 'si'
  } catch {
    return false
  }
}

function showCookieNotice() {
  if (alreadyAccepted() || document.getElementById('cookie-notice')) return

  const box = document.createElement('div')
  box.id = 'cookie-notice'
  box.setAttribute('role', 'dialog')
  box.setAttribute('aria-label', 'Aviso de cookies')
  box.className = 'fixed bottom-4 left-4 right-4 sm:left-auto sm:right-4 sm:max-w-md z-50 bg-white border border-gray-200 rounded-2xl shadow-xl p-4'
  box.innerHTML = `
    <p class="text-sm text-gray-700 mb-3">
      Comunify usa almacenamiento del navegador solo para que el sitio funcione (por ejemplo, la sesión del administrador).
      No usamos cookies de publicidad. Más información en la
      <a href="politica-cookies.html" class="text-comunify-blue underline font-medium">Política de cookies</a>.
    </p>
    <button id="cookie-accept" type="button"
      class="w-full bg-comunify-blue hover:bg-comunify-blue-dark text-white py-2.5 rounded-xl text-sm font-semibold transition-colors">
      Aceptar
    </button>
  `
  document.body.appendChild(box)

  document.getElementById('cookie-accept').addEventListener('click', () => {
    try {
      localStorage.setItem(COOKIE_KEY, 'si')
    } catch {
      /* si el navegador no deja guardar, simplemente se cierra el aviso */
    }
    box.remove()
  })
}

fillLegalData()
showCookieNotice()
