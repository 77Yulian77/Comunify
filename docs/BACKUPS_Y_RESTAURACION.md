# Backups y restauración de Comunify

## Cada cuánto se hace backup

| Qué | Frecuencia | Hora (Colombia) | Se conserva | Cómo |
|---|---|---|---|---|
| Base de datos (incidencias, suscripciones, pagos, usuarios admin) | **Diaria** | 2:00 a. m. | 30 días | `.github/workflows/backup.yml` (pg_dump cifrado) |
| Fotos de evidencia | **Semanal** (domingo) | 3:00 a. m. | 60 días | `scripts/backup-fotos.mjs` |
| Código y migraciones | Continua | cada commit | indefinido | GitHub |
| Antes de cambios grandes en la BD | Manual | — | — | Actions > Backups Comunify > Run workflow |

Metas: RPO 24 h (se pierde como máximo un día de datos) y RTO 8 h (restauración en menos de 8 horas).

## Configuración (una sola vez)

En GitHub > Settings > Secrets and variables > Actions, crea:

- `SUPABASE_DB_URL`: cadena de conexión **Session pooler** de Supabase (Project Settings > Database). Se usa el pooler porque los servidores de GitHub no tienen IPv6.
- `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`: para descargar las fotos.
- `BACKUP_PASSPHRASE`: contraseña larga para cifrar. Sin ella las copias no se pueden abrir: guárdala aparte.

## Cómo restaurar la base de datos

1. Descarga el artefacto `backup-bd-...` desde la ejecución del flujo en GitHub (pestaña Actions).
2. Descifra: `gpg --batch --passphrase "TU_CONTRASEÑA" -d comunify-db-AAAAMMDD-HHMM.sql.gz.gpg | gunzip > backup.sql`
3. Crea un proyecto nuevo de Supabase (o usa uno de pruebas) y restaura: `psql "CADENA_DE_CONEXION" -f backup.sql`
4. Verifica: número de incidencias, un ticket conocido y el ingreso del administrador.
5. Anota la prueba en el registro (fecha, responsable, resultado). Se prueba al menos una vez por semestre.

## Registro

Cada ejecución del flujo queda en GitHub > Actions con fecha, hora y resultado; ese historial es el registro de copias exigido por la política.
