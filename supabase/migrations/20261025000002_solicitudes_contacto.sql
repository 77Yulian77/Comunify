/*
# Solicitudes de contacto ("Regístrate y nosotros te contactamos")

1. Propósito
- Guardar las solicitudes que llegan desde la página principal.
- Evitar spam: máximo 3 solicitudes por correo cada 24 horas y 30 en total por hora.

2. Seguridad
- RLS activo: el público NO puede leer ni escribir la tabla directamente.
- El formulario usa la función registrar_solicitud_contacto (valida y limita).
- Solo el administrador (usuario autenticado) puede ver y marcar las solicitudes.
*/

CREATE TABLE IF NOT EXISTS solicitudes_contacto (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conjunto_nombre text NOT NULL CHECK (char_length(conjunto_nombre) BETWEEN 3 AND 120),
  contacto_nombre text NOT NULL CHECK (char_length(contacto_nombre) BETWEEN 3 AND 100),
  email text NOT NULL CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  telefono text CHECK (telefono IS NULL OR char_length(telefono) <= 20),
  mensaje text CHECK (mensaje IS NULL OR char_length(mensaje) <= 500),
  estado text NOT NULL DEFAULT 'nueva' CHECK (estado IN ('nueva', 'contactada')),
  notificada boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_solicitudes_created ON solicitudes_contacto (created_at DESC);

ALTER TABLE solicitudes_contacto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_select_solicitudes" ON solicitudes_contacto;
CREATE POLICY "auth_select_solicitudes" ON solicitudes_contacto FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_update_solicitudes" ON solicitudes_contacto;
CREATE POLICY "auth_update_solicitudes" ON solicitudes_contacto FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION registrar_solicitud_contacto(
  p_conjunto text, p_contacto text, p_email text, p_telefono text DEFAULT NULL, p_mensaje text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_email text := lower(trim(COALESCE(p_email, '')));
  v_id uuid;
BEGIN
  IF char_length(trim(COALESCE(p_conjunto, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el nombre del conjunto'; END IF;
  IF char_length(trim(COALESCE(p_contacto, ''))) < 3 THEN RAISE EXCEPTION 'Escribe tu nombre'; END IF;
  IF v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'El correo no es válido'; END IF;

  IF (SELECT count(*) FROM solicitudes_contacto WHERE lower(email) = v_email AND created_at > now() - interval '24 hours') >= 3 THEN
    RAISE EXCEPTION 'Ya recibimos varias solicitudes de este correo. Te contactaremos pronto.';
  END IF;
  IF (SELECT count(*) FROM solicitudes_contacto WHERE created_at > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Estamos recibiendo muchas solicitudes. Inténtalo de nuevo en un rato.';
  END IF;

  INSERT INTO solicitudes_contacto (conjunto_nombre, contacto_nombre, email, telefono, mensaje)
  VALUES (trim(p_conjunto), trim(p_contacto), v_email,
          NULLIF(trim(COALESCE(p_telefono, '')), ''), NULLIF(trim(COALESCE(p_mensaje, '')), ''))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION registrar_solicitud_contacto(text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION registrar_solicitud_contacto(text, text, text, text, text) TO anon, authenticated;
