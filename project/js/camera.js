import { FOTO_MAX_MB } from './validators.js'

const MAX_DIM = 1600
const MAX_BYTES = FOTO_MAX_MB * 1024 * 1024

export function cameraSupported() {
  return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)
}

function canvasToJpegFile(canvas, name) {
  // Baja la calidad poco a poco hasta que la foto quepa en el límite permitido
  const qualities = [0.85, 0.7, 0.55, 0.4]
  return new Promise((resolve, reject) => {
    const attempt = (i) => {
      canvas.toBlob((blob) => {
        if (!blob) return reject(new Error('No se pudo procesar la foto'))
        if (blob.size <= MAX_BYTES || i === qualities.length - 1) {
          resolve(new File([blob], name, { type: 'image/jpeg' }))
        } else {
          attempt(i + 1)
        }
      }, 'image/jpeg', qualities[i])
    }
    attempt(0)
  })
}

function drawScaled(source, width, height) {
  const scale = Math.min(1, MAX_DIM / Math.max(width, height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(width * scale)
  canvas.height = Math.round(height * scale)
  canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height)
  return canvas
}

function loadImage(blob) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(blob)
    const img = new Image()
    img.onload = () => { URL.revokeObjectURL(url); resolve(img) }
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('No se pudo leer la imagen')) }
    img.src = url
  })
}

// Reduce el tamaño de una foto (por ejemplo la que viene del celular) y la deja en JPG
export async function compressImage(file) {
  const img = await loadImage(file)
  const canvas = drawScaled(img, img.naturalWidth, img.naturalHeight)
  return canvasToJpegFile(canvas, `foto-${Date.now()}.jpg`)
}

// Abre la cámara en una ventana y devuelve la foto tomada (File) o null si se cancela
export function openCameraModal() {
  return new Promise((resolve, reject) => {
    let stream = null
    let facingMode = 'environment'
    let closed = false

    const overlay = document.createElement('div')
    overlay.className = 'fixed inset-0 z-50 modal-backdrop flex items-center justify-center p-4'
    overlay.innerHTML = `
      <div class="bg-white rounded-2xl overflow-hidden w-full max-w-lg card-shadow">
        <div class="bg-black relative">
          <video id="cam-video" class="w-full max-h-[60vh] object-contain" autoplay playsinline muted></video>
          <p id="cam-loading" class="absolute inset-0 flex items-center justify-center text-white text-sm">Abriendo cámara...</p>
        </div>
        <div class="p-4 flex items-center justify-between gap-3">
          <button type="button" id="cam-cancel" class="px-4 py-3 border border-gray-300 rounded-xl text-sm font-semibold text-gray-700 hover:bg-gray-50">Cancelar</button>
          <button type="button" id="cam-flip" class="hidden px-4 py-3 border border-gray-300 rounded-xl text-sm font-semibold text-gray-700 hover:bg-gray-50">Girar cámara</button>
          <button type="button" id="cam-capture" disabled class="flex-1 bg-comunify-blue hover:bg-comunify-blue-dark disabled:opacity-50 text-white px-4 py-3 rounded-xl text-sm font-semibold flex items-center justify-center gap-2">
            <i data-lucide="camera" class="w-5 h-5"></i> Tomar foto
          </button>
        </div>
      </div>
    `
    document.body.appendChild(overlay)
    if (window.lucide) window.lucide.createIcons()

    const video = overlay.querySelector('#cam-video')
    const loading = overlay.querySelector('#cam-loading')
    const btnCapture = overlay.querySelector('#cam-capture')
    const btnFlip = overlay.querySelector('#cam-flip')
    const btnCancel = overlay.querySelector('#cam-cancel')

    function stopStream() {
      if (stream) stream.getTracks().forEach((t) => t.stop())
      stream = null
    }

    function close(result, error) {
      if (closed) return
      closed = true
      stopStream()
      document.removeEventListener('keydown', onKey)
      overlay.remove()
      if (error) reject(error)
      else resolve(result)
    }

    function onKey(e) {
      if (e.key === 'Escape') close(null)
    }
    document.addEventListener('keydown', onKey)

    async function start() {
      stopStream()
      btnCapture.disabled = true
      loading.classList.remove('hidden')
      try {
        const s = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: facingMode } },
          audio: false,
        })
        if (closed) { s.getTracks().forEach((t) => t.stop()); return }
        stream = s
        video.srcObject = s
        await video.play().catch(() => {})
        loading.classList.add('hidden')
        btnCapture.disabled = false

        const devices = await navigator.mediaDevices.enumerateDevices()
        if (devices.filter((d) => d.kind === 'videoinput').length > 1) {
          btnFlip.classList.remove('hidden')
        }
      } catch (err) {
        close(null, err)
      }
    }

    btnCancel.addEventListener('click', () => close(null))
    overlay.addEventListener('click', (e) => { if (e.target === overlay) close(null) })

    btnFlip.addEventListener('click', () => {
      facingMode = facingMode === 'environment' ? 'user' : 'environment'
      start()
    })

    btnCapture.addEventListener('click', async () => {
      if (!video.videoWidth) return
      btnCapture.disabled = true
      try {
        const canvas = drawScaled(video, video.videoWidth, video.videoHeight)
        const file = await canvasToJpegFile(canvas, `foto-${Date.now()}.jpg`)
        close(file)
      } catch (err) {
        close(null, err)
      }
    })

    start()
  })
}
