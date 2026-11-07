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
/*
# Arreglo del error "incidencias_foto_url_https" + eliminar con copia de respaldo

1. Problema
- Al resolver un ticket aparecía: violates check constraint "incidencias_foto_url_https".
- Esa regla (creada a mano en tu base, no está en las migraciones) revisa foto_url en CADA actualización;
  si el ticket tiene una foto_url antigua que no empieza por https, no deja guardar ningún cambio.

2. Arreglo
- Se reemplaza la regla por una equivalente (foto_url vacía o que empiece por https://).
- Los tickets con una foto_url inválida (no https) quedan con foto_url vacía para poder editarlos.
  Esas fotos ya no cargaban en el panel. Para verlos antes de ejecutar:
    SELECT ticket_number, foto_url FROM incidencias WHERE foto_url IS NOT NULL AND foto_url !~* '^https://';

3. Eliminar con respaldo
- Tabla incidencias_respaldo: copia del ticket eliminado (solo visible en Supabase, no en la app).
- Función eliminar_con_respaldo(tickets): copia y luego borra del panel. Las fotos se conservan.
- Función restaurar_respaldo(ticket): devuelve un ticket del respaldo a incidencias.

4. Políticas
- Se vuelven a crear la de UPDATE (admin) y DELETE para asegurar que estén como la app las necesita.
*/

-- ===== 1. Regla de foto_url =====
ALTER TABLE incidencias DROP CONSTRAINT IF EXISTS incidencias_foto_url_https;
UPDATE incidencias SET foto_url = NULL WHERE foto_url IS NOT NULL AND foto_url !~* '^https://';
ALTER TABLE incidencias ADD CONSTRAINT incidencias_foto_url_https
  CHECK (foto_url IS NULL OR foto_url ~* '^https://');

-- ===== 2. Políticas del administrador =====
DROP POLICY IF EXISTS "auth_update_incidencias" ON incidencias;
CREATE POLICY "auth_update_incidencias"
  ON incidencias FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "auth_delete_incidencias" ON incidencias;
CREATE POLICY "auth_delete_incidencias"
  ON incidencias FOR DELETE TO authenticated USING (true);

-- ===== 3. Respaldo de tickets eliminados =====
CREATE TABLE IF NOT EXISTS incidencias_respaldo (LIKE incidencias);
ALTER TABLE incidencias_respaldo ADD COLUMN IF NOT EXISTS eliminada_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE incidencias_respaldo ADD COLUMN IF NOT EXISTS eliminada_por uuid;
CREATE UNIQUE INDEX IF NOT EXISTS incidencias_respaldo_ticket_uq ON incidencias_respaldo (ticket_number);
-- RLS activado y sin políticas: nadie la lee desde la app; solo se usa mediante las funciones de abajo
ALTER TABLE incidencias_respaldo ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION eliminar_con_respaldo(p_tickets text[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;

  DELETE FROM incidencias_respaldo WHERE ticket_number = ANY (p_tickets);
  INSERT INTO incidencias_respaldo
    SELECT i.*, now(), auth.uid() FROM incidencias i WHERE i.ticket_number = ANY (p_tickets);

  DELETE FROM incidencias WHERE ticket_number = ANY (p_tickets);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION restaurar_respaldo(p_ticket text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  INSERT INTO incidencias
    SELECT * FROM jsonb_populate_record(NULL::incidencias,
      (SELECT to_jsonb(r) - 'eliminada_at' - 'eliminada_por' FROM incidencias_respaldo r WHERE r.ticket_number = p_ticket));
  DELETE FROM incidencias_respaldo WHERE ticket_number = p_ticket;
END;
$$;

REVOKE ALL ON FUNCTION eliminar_con_respaldo(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION restaurar_respaldo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION eliminar_con_respaldo(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION restaurar_respaldo(text) TO authenticated;
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
/*
# Ver, restaurar y borrar los tickets guardados en el respaldo

1. Propósito
- Los tickets eliminados con "copia de respaldo" quedan en incidencias_respaldo, que la app no podía leer.
- Estas funciones permiten a un administrador ver el respaldo, restaurar un ticket al panel
  o borrarlo del respaldo para siempre. Solo usuarios autenticados.

2. Cambios
- listar_respaldo(): devuelve los tickets del respaldo.
- borrar_de_respaldo(tickets): los borra del respaldo (las fotos las borra la app).
- No modifica datos existentes.
*/

CREATE OR REPLACE FUNCTION listar_respaldo()
RETURNS SETOF incidencias_respaldo LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  RETURN QUERY SELECT * FROM incidencias_respaldo ORDER BY eliminada_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION borrar_de_respaldo(p_tickets text[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  DELETE FROM incidencias_respaldo WHERE ticket_number = ANY (p_tickets);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION listar_respaldo() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION borrar_de_respaldo(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION listar_respaldo() TO authenticated;
GRANT EXECUTE ON FUNCTION borrar_de_respaldo(text[]) TO authenticated;
/*
# Separar los tickets por conjunto

1. Problema
- Cualquier cuenta de administrador veía TODOS los tickets (la política de lectura era pública).

2. Cambios
- Tabla conjuntos (slug, nombre). Se crea 'monteclaro'. Para agregar otro: ver supabase/scripts/crear_conjunto_y_cuenta.sql
- incidencias.conjunto (y en el respaldo): los tickets existentes quedan en 'monteclaro'.
- El conjunto de un ticket nuevo viene del enlace/QR de reporte (reportar.html?conjunto=slug); si no trae, queda en 'monteclaro'.
- CADA cuenta ve SOLO los tickets de su conjunto (app_metadata.conjunto), también la de Comunify:
  admin@comunify.app queda en el conjunto 'comunify' y admin.monteclaro@comunify.app en 'monteclaro'.
  El rol 'admin' solo da Solicitudes y Generar QR, ya no da acceso a los tickets de otros conjuntos.
- Un ticket sin conjunto en el enlace queda en 'comunify'.
- Políticas y funciones de respaldo respetan esa separación.
- El residente sigue consultando su ticket por número aunque se haya eliminado con copia de respaldo
  (función consultar_ticket). Si se elimina DEFINITIVAMENTE, ya no existe.
- Después de ejecutar: cerrar sesión y volver a entrar en cada cuenta.
*/

-- ===== Conjuntos =====
CREATE TABLE IF NOT EXISTS conjuntos (
  slug text PRIMARY KEY CHECK (slug ~ '^[a-z0-9-]{2,40}$'),
  nombre text NOT NULL CHECK (char_length(nombre) BETWEEN 3 AND 120),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE conjuntos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_select_conjuntos" ON conjuntos;
CREATE POLICY "public_select_conjuntos" ON conjuntos FOR SELECT TO anon, authenticated USING (true);
GRANT SELECT ON conjuntos TO anon, authenticated;

INSERT INTO conjuntos (slug, nombre) VALUES
  ('comunify', 'Comunify (cuenta principal)'),
  ('monteclaro', 'Conjunto Residencial Monteclaro P.H.')
ON CONFLICT (slug) DO NOTHING;

-- ===== Columna conjunto =====
ALTER TABLE incidencias ADD COLUMN IF NOT EXISTS conjunto text NOT NULL DEFAULT 'comunify' REFERENCES conjuntos(slug) ON UPDATE CASCADE;
ALTER TABLE incidencias ALTER COLUMN conjunto SET DEFAULT 'comunify';
CREATE INDEX IF NOT EXISTS idx_incidencias_conjunto ON incidencias (conjunto);
ALTER TABLE incidencias_respaldo ADD COLUMN IF NOT EXISTS conjunto text NOT NULL DEFAULT 'comunify';
ALTER TABLE incidencias_respaldo ALTER COLUMN conjunto SET DEFAULT 'comunify';

-- ===== Quién es quién (viene del token, el usuario no puede cambiarlo) =====
CREATE OR REPLACE FUNCTION es_admin_comunify() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
$$;
CREATE OR REPLACE FUNCTION mi_conjunto() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT auth.jwt() -> 'app_metadata' ->> 'conjunto'
$$;
GRANT EXECUTE ON FUNCTION es_admin_comunify() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mi_conjunto() TO anon, authenticated;

-- ===== Políticas de incidencias =====
-- anon: sigue leyendo (consultar por número de ticket). Antes la política también incluía a authenticated.
DROP POLICY IF EXISTS "anon_select_incidencias" ON incidencias;
CREATE POLICY "anon_select_incidencias" ON incidencias FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "auth_select_incidencias" ON incidencias;
CREATE POLICY "auth_select_incidencias" ON incidencias FOR SELECT TO authenticated
  USING (conjunto = mi_conjunto());

DROP POLICY IF EXISTS "auth_update_incidencias" ON incidencias;
CREATE POLICY "auth_update_incidencias" ON incidencias FOR UPDATE TO authenticated
  USING (conjunto = mi_conjunto())
  WITH CHECK (conjunto = mi_conjunto());

DROP POLICY IF EXISTS "auth_delete_incidencias" ON incidencias;
CREATE POLICY "auth_delete_incidencias" ON incidencias FOR DELETE TO authenticated
  USING (conjunto = mi_conjunto());

-- ===== Respaldo: ahora por nombre de columna y por conjunto =====
CREATE OR REPLACE FUNCTION eliminar_con_respaldo(p_tickets text[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ok text[]; v_n integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT array_agg(ticket_number) INTO v_ok FROM incidencias
   WHERE ticket_number = ANY (p_tickets) AND (conjunto = mi_conjunto());
  IF v_ok IS NULL THEN RETURN 0; END IF;

  DELETE FROM incidencias_respaldo WHERE ticket_number = ANY (v_ok);
  INSERT INTO incidencias_respaldo
    SELECT (jsonb_populate_record(NULL::incidencias_respaldo,
             to_jsonb(i) || jsonb_build_object('eliminada_at', now(), 'eliminada_por', auth.uid()))).*
    FROM incidencias i WHERE i.ticket_number = ANY (v_ok);

  DELETE FROM incidencias WHERE ticket_number = ANY (v_ok);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION restaurar_respaldo(p_ticket text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row incidencias_respaldo;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  SELECT * INTO v_row FROM incidencias_respaldo
   WHERE ticket_number = p_ticket AND (conjunto = mi_conjunto());
  IF NOT FOUND THEN RAISE EXCEPTION 'Ticket no encontrado en el respaldo'; END IF;
  INSERT INTO incidencias
    SELECT * FROM jsonb_populate_record(NULL::incidencias, to_jsonb(v_row) - 'eliminada_at' - 'eliminada_por');
  DELETE FROM incidencias_respaldo WHERE ticket_number = p_ticket;
END;
$$;

CREATE OR REPLACE FUNCTION listar_respaldo()
RETURNS SETOF incidencias_respaldo LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  RETURN QUERY SELECT * FROM incidencias_respaldo
    WHERE conjunto = mi_conjunto()
    ORDER BY eliminada_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION borrar_de_respaldo(p_tickets text[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'No autorizado'; END IF;
  DELETE FROM incidencias_respaldo
   WHERE ticket_number = ANY (p_tickets) AND (conjunto = mi_conjunto());
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- ===== El residente sigue viendo su ticket aunque se haya eliminado con copia de respaldo =====
CREATE OR REPLACE FUNCTION consultar_ticket(p_ticket text)
RETURNS TABLE (ticket_number text, descripcion text, torre text, piso int, zona text, foto_url text, estado text,
               created_at timestamptz, resolucion_comentario text, resolucion_foto_url text, resuelta_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT i.ticket_number, i.descripcion, i.torre, i.piso, i.zona, i.foto_url, i.estado,
         i.created_at, i.resolucion_comentario, i.resolucion_foto_url, i.resuelta_at
  FROM incidencias i WHERE i.ticket_number = upper(trim(p_ticket))
  UNION ALL
  SELECT r.ticket_number, r.descripcion, r.torre, r.piso, r.zona, r.foto_url, r.estado,
         r.created_at, r.resolucion_comentario, r.resolucion_foto_url, r.resuelta_at
  FROM incidencias_respaldo r WHERE r.ticket_number = upper(trim(p_ticket))
    AND NOT EXISTS (SELECT 1 FROM incidencias x WHERE x.ticket_number = r.ticket_number)
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION consultar_ticket(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consultar_ticket(text) TO anon, authenticated;

-- ===== Cuentas asignadas a su conjunto =====
UPDATE auth.users
SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"role":"conjunto","conjunto":"monteclaro"}'::jsonb
WHERE email = 'admin.monteclaro@comunify.app';

UPDATE auth.users
SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin","conjunto":"comunify"}'::jsonb
WHERE email = 'admin@comunify.app';
