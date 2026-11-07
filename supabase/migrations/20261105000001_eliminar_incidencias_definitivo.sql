/*
# Permitir al administrador eliminar tickets definitivamente

1. Propósito
- El panel ahora tiene "Eliminar definitivamente" (por ticket o por selección), en cualquier estado.
- Reemplaza la regla anterior que solo dejaba borrar tickets "Resuelto".

2. Cambios
- Política DELETE en incidencias: cualquier usuario autenticado (administrador).
- Política DELETE en storage.objects del bucket incidencia-fotos: usuarios autenticados,
  para poder borrar también la foto del ticket.
- No modifica datos existentes. Los visitantes (anon) siguen sin poder borrar nada.
*/

DROP POLICY IF EXISTS "auth_delete_incidencias" ON incidencias;
CREATE POLICY "auth_delete_incidencias"
  ON incidencias FOR DELETE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "auth_delete_fotos_incidencias" ON storage.objects;
CREATE POLICY "auth_delete_fotos_incidencias"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'incidencia-fotos');
