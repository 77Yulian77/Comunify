/*
# Solo se pueden eliminar tickets resueltos

1. Propósito
- El panel del administrador ahora permite eliminar tickets en estado "Resuelto".
- Esta política hace que la base de datos también lo exija: aunque alguien intente borrar
  un ticket Pendiente o En Proceso, la base de datos no lo permite.

2. Cambios
- Reemplaza la política auth_delete_incidencias: DELETE solo para usuarios autenticados
  y solo cuando estado = 'Resuelto'.
- No modifica datos existentes.
*/

DROP POLICY IF EXISTS "auth_delete_incidencias" ON incidencias;
CREATE POLICY "auth_delete_incidencias"
  ON incidencias FOR DELETE
  TO authenticated
  USING (estado = 'Resuelto');
