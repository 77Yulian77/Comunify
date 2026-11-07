/*
# Comentario y foto al resolver un ticket

1. Propósito
- Al marcar un ticket como "Resuelto", el administrador deja un comentario y una foto de cómo quedó.
- Se guardan con el ticket (también cuando se archiva) y se ven al consultarlo por su número.

2. Cambios
- Columnas nuevas en incidencias: resolucion_comentario, resolucion_foto_url, resuelta_at.
- No modifica ni borra datos existentes (los tickets resueltos antiguos quedan sin comentario ni foto).
- La foto usa el mismo bucket incidencia-fotos y sus políticas actuales.
*/

ALTER TABLE incidencias ADD COLUMN IF NOT EXISTS resolucion_comentario text;
ALTER TABLE incidencias ADD COLUMN IF NOT EXISTS resolucion_foto_url text;
ALTER TABLE incidencias ADD COLUMN IF NOT EXISTS resuelta_at timestamptz;

ALTER TABLE incidencias DROP CONSTRAINT IF EXISTS incidencias_resolucion_comentario_largo;
ALTER TABLE incidencias ADD CONSTRAINT incidencias_resolucion_comentario_largo
  CHECK (resolucion_comentario IS NULL OR char_length(resolucion_comentario) <= 500);
