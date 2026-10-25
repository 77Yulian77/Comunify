/*
# Archivar tickets resueltos en vez de eliminarlos

1. Propósito
- Los tickets resueltos ya no se borran: se ARCHIVAN. Dejan de verse en el panel del administrador,
  pero siguen existiendo y se pueden consultar con su número de ticket (consultar.html).
- Un ticket archivado se puede restaurar desde la pestaña "Archivados" del panel.

2. Cambios
- Columnas nuevas en incidencias: archivada (boolean, por defecto false) y archivada_at.
- Regla en la base de datos: solo se puede archivar un ticket en estado "Resuelto".
- No se modifican ni se borran datos existentes: todos los tickets actuales quedan activos.
*/

ALTER TABLE incidencias ADD COLUMN IF NOT EXISTS archivada boolean NOT NULL DEFAULT false;
ALTER TABLE incidencias ADD COLUMN IF NOT EXISTS archivada_at timestamptz;

ALTER TABLE incidencias DROP CONSTRAINT IF EXISTS incidencias_archivada_solo_resueltas;
ALTER TABLE incidencias ADD CONSTRAINT incidencias_archivada_solo_resueltas
  CHECK (NOT archivada OR estado = 'Resuelto');

CREATE INDEX IF NOT EXISTS idx_incidencias_archivada ON incidencias (archivada);
