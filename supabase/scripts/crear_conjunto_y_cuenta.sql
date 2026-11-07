-- Agregar un conjunto nuevo y asignarle una cuenta ya creada en Authentication → Users.
-- 1) Crea el usuario en Supabase (Authentication → Users → Add user, "Auto Confirm User").
-- 2) Cambia los 3 valores de abajo y ejecuta. 3) Esa persona cierra sesión y vuelve a entrar.
-- 4) En "Generar QR" (cuenta admin de Comunify) aparecerá el conjunto nuevo para sus QR.

DO $$
DECLARE
  v_slug   text := 'nuevo-conjunto';                       -- <-- minúsculas, sin espacios (ej. 'altos-del-parque')
  v_nombre text := 'Conjunto Residencial Nuevo P.H.';      -- <-- nombre que verá la gente
  v_email  text := 'admin.nuevo@comunify.app';             -- <-- correo de la cuenta ya creada
BEGIN
  INSERT INTO conjuntos (slug, nombre) VALUES (v_slug, v_nombre)
    ON CONFLICT (slug) DO UPDATE SET nombre = EXCLUDED.nombre;
  UPDATE auth.users
     SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'conjunto', 'conjunto', v_slug)
   WHERE email = v_email;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe un usuario con el correo %', v_email; END IF;
END $$;
