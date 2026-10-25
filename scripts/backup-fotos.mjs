// Descarga todas las fotos del bucket "incidencia-fotos" a una carpeta local.
// Uso: node backup-fotos.mjs <carpeta_destino>
import { createClient } from '@supabase/supabase-js'
import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'

const BUCKET = 'incidencia-fotos'
const destino = process.argv[2] || './backup-fotos'
const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY')
  process.exit(1)
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
await mkdir(destino, { recursive: true })

let total = 0
let offset = 0
const PAGE = 100

while (true) {
  const { data, error } = await supabase.storage.from(BUCKET).list('', { limit: PAGE, offset })
  if (error) throw error
  if (!data.length) break

  for (const f of data) {
    if (!f.name || f.id === null) continue // carpetas
    const { data: blob, error: errDown } = await supabase.storage.from(BUCKET).download(f.name)
    if (errDown) throw errDown
    await writeFile(path.join(destino, f.name), Buffer.from(await blob.arrayBuffer()))
    total++
  }
  if (data.length < PAGE) break
  offset += PAGE
}

console.log(`Fotos respaldadas: ${total}`)
