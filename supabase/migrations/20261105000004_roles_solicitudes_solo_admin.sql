/*
# Solicitudes solo para el administrador de Comunify

1. Propósito
- Las cuentas de conjunto (ej. Monteclaro) ya no ven ni pueden leer las solicitudes de contacto.
- El botón se oculta en la app y además la base lo exige (no basta con ocultarlo).

2. Cambios
- El usuario admin@comunify.app queda con role = 'admin' en app_metadata (si existe).
- Políticas de solicitudes_contacto: SELECT/UPDATE solo si el token trae role = 'admin'.
- IMPORTANTE: cierra sesión y vuelve a entrar para que el token traiga el rol.
- Si tu administrador usa OTRO correo, cámbialo en la línea del UPDATE antes de ejecutar.
*/

UPDATE auth.users
SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
WHERE email = 'admin@comunify.app';

-- Cualquier otra cuenta que tuviera role = 'admin' (ej. una creada con la migración antigua o con un SQL previo)
-- pasa a cuenta de conjunto.
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role":"conjunto"}'::jsonb
WHERE email <> 'admin@comunify.app' AND raw_app_meta_data ->> 'role' = 'admin';

-- Comprobación (debe verse admin solo en admin@comunify.app):
-- SELECT email, raw_app_meta_data ->> 'role' AS rol FROM auth.users;

DROP POLICY IF EXISTS "auth_select_solicitudes" ON solicitudes_contacto;
CREATE POLICY "auth_select_solicitudes" ON solicitudes_contacto
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "auth_update_solicitudes" ON solicitudes_contacto;
CREATE POLICY "auth_update_solicitudes" ON solicitudes_contacto
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
