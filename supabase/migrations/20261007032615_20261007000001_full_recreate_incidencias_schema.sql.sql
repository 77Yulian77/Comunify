/*
# Comunify - Recreación completa del esquema con correcciones CC-004 y CC-005

1. Propósito
- La base de datos estaba vacía: ninguna migración previa había sido aplicada.
- Esta migración crea todo el esquema desde cero con las correcciones ya incluidas:
  - CC-005: el constraint de piso permite 1-17 (no 1-10 como en la versión original).
  - CC-004: el usuario administrador se crea con su identidad de correo para que el login funcione.

2. Tablas
- `incidencias`: reportes de incidencias de residentes del Conjunto Residencial Monteclaro P.H.
  - `id` (uuid, primary key)
  - `ticket_number` (text, unique, formato TCK-2026-XXX, generado por secuencia)
  - `descripcion` (text, not null)
  - `torre` (text, not null, A/B/C)
  - `piso` (int, not null, 1-17)  -- CC-005: rango ampliado a 17
  - `zona` (text, not null: pasillo, parqueadero, ascensor, zonas_verdes, lobby)
  - `foto_url` (text, nullable)
  - `residente_nombre` (text, nullable)
  - `estado` (text, not null, default 'Pendiente': Pendiente, En Proceso, Resuelto)
  - `created_at` (timestamptz, default now())

3. Seguridad
- RLS habilitado en `incidencias`.
- anon + authenticated: SELECT e INSERT (sistema público de reportes).
- authenticated: UPDATE y DELETE (solo administradores).

4. Usuario administrador (CC-004)
- Crea admin@comunify.app con contraseña Admin2026!
- Crea la identidad de correo (provider = 'email') para que el login funcione.

5. Políticas de Storage
- Bucket 'incidencia-fotos': anon puede subir y leer fotos; authenticated puede eliminar.

6. Notas
- Los números de ticket usan una secuencia PostgreSQL para unicidad.
- Las fotos se almacenan en el bucket 'incidencia-fotos' de Supabase Storage.
- No hay foreign keys a auth.users: es un sistema público de reportes.
*/

-- ==============================
-- Secuencia para ticket_number
-- ==============================
CREATE SEQUENCE IF NOT EXISTS incidencia_ticket_seq
  START WITH 1
  INCREMENT BY 1
  NO CYCLE;

-- ==============================
-- Tabla incidencias
-- ==============================
CREATE TABLE IF NOT EXISTS incidencias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number text UNIQUE NOT NULL DEFAULT ('TCK-2026-' || lpad(nextval('incidencia_ticket_seq')::text, 3, '0')),
  descripcion text NOT NULL,
  torre text NOT NULL CHECK (torre IN ('A', 'B', 'C')),
  piso int NOT NULL CHECK (piso >= 1 AND piso <= 17),
  zona text NOT NULL CHECK (zona IN ('pasillo', 'parqueadero', 'ascensor', 'zonas_verdes', 'lobby')),
  foto_url text,
  residente_nombre text,
  estado text NOT NULL DEFAULT 'Pendiente' CHECK (estado IN ('Pendiente', 'En Proceso', 'Resuelto')),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE incidencias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_incidencias" ON incidencias;
CREATE POLICY "anon_select_incidencias"
  ON incidencias FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "anon_insert_incidencias" ON incidencias;
CREATE POLICY "anon_insert_incidencias"
  ON incidencias FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "auth_update_incidencias" ON incidencias;
CREATE POLICY "auth_update_incidencias"
  ON incidencias FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "auth_delete_incidencias" ON incidencias;
CREATE POLICY "auth_delete_incidencias"
  ON incidencias FOR DELETE
  TO authenticated
  USING (true);

CREATE INDEX IF NOT EXISTS idx_incidencias_ticket_number ON incidencias(ticket_number);
CREATE INDEX IF NOT EXISTS idx_incidencias_estado ON incidencias(estado);
CREATE INDEX IF NOT EXISTS idx_incidencias_torre_piso ON incidencias(torre, piso);

-- ==============================
-- Políticas de Storage
-- ==============================
DROP POLICY IF EXISTS "anon_upload_fotos" ON storage.objects;
CREATE POLICY "anon_upload_fotos"
  ON storage.objects FOR INSERT
  TO anon, authenticated
  WITH CHECK (bucket_id = 'incidencia-fotos');

DROP POLICY IF EXISTS "anon_read_fotos" ON storage.objects;
CREATE POLICY "anon_read_fotos"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'incidencia-fotos');

DROP POLICY IF EXISTS "auth_delete_fotos" ON storage.objects;
CREATE POLICY "auth_delete_fotos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'incidencia-fotos');

-- ==============================
-- CC-004: Crear usuario administrador + identidad de correo
-- ==============================
DO $$
DECLARE
  admin_email   text := 'admin@comunify.app';
  admin_user_id uuid;
BEGIN
  SELECT id INTO admin_user_id
  FROM auth.users
  WHERE email = admin_email
  LIMIT 1;

  IF admin_user_id IS NULL THEN
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      created_at,
      updated_at,
      raw_app_meta_data,
      raw_user_meta_data,
      email_change_confirm_status
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      admin_email,
      crypt('Admin2026!', gen_salt('bf')),
      now(),
      now(),
      now(),
      '{"role":"admin"}'::jsonb,
      '{}'::jsonb,
      0
    )
    RETURNING id INTO admin_user_id;

    RAISE NOTICE 'Usuario administrador creado: %', admin_email;
  ELSE
    RAISE NOTICE 'El usuario administrador ya existía: %', admin_email;
  END IF;

  -- Crear identidad de correo si no existe
  IF NOT EXISTS (
    SELECT 1 FROM auth.identities
    WHERE user_id = admin_user_id AND provider = 'email'
  ) THEN
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      admin_user_id,
      jsonb_build_object(
        'sub', admin_user_id::text,
        'email', admin_email,
        'email_verified', true,
        'phone_verified', false
      ),
      'email',
      admin_user_id::text,
      now(),
      now()
    );
    RAISE NOTICE 'Identidad de correo creada para %', admin_email;
  ELSE
    RAISE NOTICE 'La identidad de correo ya existía para %', admin_email;
  END IF;
END $$;
