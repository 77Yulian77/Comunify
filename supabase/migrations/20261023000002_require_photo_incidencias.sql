/*
# La foto de evidencia es obligatoria al crear una incidencia

1. Propósito
- El formulario de reporte ahora exige adjuntar una foto.
- Esta política hace que la base de datos también lo exija: no se puede crear un ticket sin foto_url.

2. Cambios
- Reemplaza la política anon_insert_incidencias: INSERT solo si foto_url no está vacío.
- No modifica los tickets que ya existen (aunque no tengan foto).
*/

DROP POLICY IF EXISTS "anon_insert_incidencias" ON incidencias;
CREATE POLICY "anon_insert_incidencias"
  ON incidencias FOR INSERT
  TO anon, authenticated
  WITH CHECK (foto_url IS NOT NULL AND length(trim(foto_url)) > 0);
