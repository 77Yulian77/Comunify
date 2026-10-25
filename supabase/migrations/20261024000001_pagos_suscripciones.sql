/*
# Módulo financiero: suscripciones y pagos (pasarela Wompi, Colombia)

1. Propósito
- Registrar los conjuntos residenciales que contratan Comunify (modelo SaaS por suscripción mensual).
- Registrar cada pago hecho por la pasarela Wompi (cuota de instalación + mensualidades).

2. Tablas
- suscripciones: un registro por conjunto (nit único). Estados: pendiente, activa, vencida, cancelada.
- pagos: un registro por intento de pago (reference única). Estados de Wompi: PENDING, APPROVED, DECLINED, VOIDED, ERROR.

3. Seguridad
- RLS activo en ambas tablas.
- Anónimos NO leen ni escriben: solo las Edge Functions (service role) crean y actualizan pagos.
- Usuarios autenticados (administrador) solo pueden leer.
- La página de resultado consulta el estado con la función consultar_pago(reference), que solo
  devuelve estado y total (sin datos personales).

4. Valores (según el documento del proyecto, Tabla 1 - FIN-01)
- Suscripción mensual por conjunto: 450.000 COP. Cuota de instalación: 2.000.000 COP (única vez).
  Los montos NO se guardan aquí como reglas: el servidor los calcula en la función crear-pago.
*/

CREATE TABLE IF NOT EXISTS suscripciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conjunto_nombre text NOT NULL CHECK (char_length(conjunto_nombre) BETWEEN 3 AND 120),
  nit text NOT NULL UNIQUE CHECK (char_length(nit) BETWEEN 5 AND 20),
  contacto_nombre text NOT NULL CHECK (char_length(contacto_nombre) BETWEEN 3 AND 100),
  email text NOT NULL CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  telefono text,
  estado text NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'activa', 'vencida', 'cancelada')),
  meses_pagados integer NOT NULL DEFAULT 0 CHECK (meses_pagados >= 0),
  inicio timestamptz,
  proximo_cobro timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pagos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reference text NOT NULL UNIQUE,
  suscripcion_id uuid NOT NULL REFERENCES suscripciones(id) ON DELETE RESTRICT,
  tipo text NOT NULL CHECK (tipo IN ('alta', 'renovacion')),
  meses integer NOT NULL CHECK (meses BETWEEN 1 AND 12),
  incluye_instalacion boolean NOT NULL DEFAULT false,
  subtotal_cop bigint NOT NULL CHECK (subtotal_cop > 0),
  iva_cop bigint NOT NULL DEFAULT 0 CHECK (iva_cop >= 0),
  total_cop bigint NOT NULL CHECK (total_cop > 0),
  estado text NOT NULL DEFAULT 'PENDING'
    CHECK (estado IN ('PENDING', 'APPROVED', 'DECLINED', 'VOIDED', 'ERROR')),
  wompi_transaction_id text,
  metodo_pago text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pagos_suscripcion ON pagos (suscripcion_id);
CREATE INDEX IF NOT EXISTS idx_suscripciones_proximo_cobro ON suscripciones (proximo_cobro);

ALTER TABLE suscripciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_select_suscripciones" ON suscripciones;
CREATE POLICY "auth_select_suscripciones"
  ON suscripciones FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "auth_select_pagos" ON pagos;
CREATE POLICY "auth_select_pagos"
  ON pagos FOR SELECT TO authenticated USING (true);

-- Estado de un pago por su referencia (para la página de resultado). Sin datos personales.
CREATE OR REPLACE FUNCTION consultar_pago(p_reference text)
RETURNS TABLE (reference text, estado text, total_cop bigint, created_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.reference, p.estado, p.total_cop, p.created_at
  FROM pagos p
  WHERE p.reference = p_reference
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION consultar_pago(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consultar_pago(text) TO anon, authenticated;
