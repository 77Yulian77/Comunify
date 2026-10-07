import { defineConfig } from 'vite'
import { resolve } from 'path'

export default defineConfig({
  root: '.',
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        reportar: resolve(__dirname, 'reportar.html'),
        consultar: resolve(__dirname, 'consultar.html'),
        login: resolve(__dirname, 'login.html'),
        dashboard: resolve(__dirname, 'dashboard.html'),
        qrGenerator: resolve(__dirname, 'qr-generator.html'),
      },
    },
  },
})
