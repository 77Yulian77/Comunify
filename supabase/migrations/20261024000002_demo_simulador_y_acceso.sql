/*
# Prueba gratuita de 7 días, simulador de pagos y bloqueo de la plataforma

1. Propósito
- Permitir que un conjunto pruebe Comunify GRATIS durante 7 días (sin tarjeta).
- Permitir pagar en modo SIMULADO (como el simulador de un banco): funciona sin cuenta de Wompi
  y no mueve dinero real. Se cambia a Wompi real con un solo valor de configuración.
- Bloquear la plataforma (crear reportes) cuando no hay una suscripción activa ni una prueba vigente.

2. Configuración (tabla configuracion)
- modo_pagos: 'simulado' (demo) o 'wompi' (real).
- exigir_suscripcion: 'true' bloquea la plataforma sin suscripción; 'false' la deja libre.

3. Seguridad
- Todo se hace con funciones SECURITY DEFINER; las tablas siguen cerradas al público.
- La regla "sin suscripción no se crean incidencias" se aplica en la base de datos (política RLS),
  no solo en la pantalla.
- simular_pago solo funciona cuando modo_pagos = 'simulado'.

4. Supuesto
- Comunify atiende hoy un solo conjunto (piloto Monteclaro): el acceso es global. Si se atendieran
  varios conjuntos, habría que ligar cada incidencia a su suscripción.
*/

-- ===== Estados nuevos y fecha de fin de la prueba =====
ALTER TABLE suscripciones ADD COLUMN IF NOT EXISTS prueba_hasta timestamptz;
ALTER TABLE suscripciones DROP CONSTRAINT IF EXISTS suscripciones_estado_check;
ALTER TABLE suscripciones ADD CONSTRAINT suscripciones_estado_check
  CHECK (estado IN ('pendiente', 'prueba', 'activa', 'vencida', 'cancelada'));

-- ===== Configuración =====
CREATE TABLE IF NOT EXISTS configuracion (
  clave text PRIMARY KEY,
  valor text NOT NULL
);
ALTER TABLE configuracion ENABLE ROW LEVEL SECURITY;

INSERT INTO configuracion (clave, valor) VALUES
  ('modo_pagos', 'simulado'),
  ('exigir_suscripcion', 'true')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION modo_pagos()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT valor FROM configuracion WHERE clave = 'modo_pagos'), 'simulado');
$$;

-- ===== Estado de la plataforma (sin datos personales) =====
CREATE OR REPLACE FUNCTION estado_plataforma()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_exigir boolean;
  v_pagado timestamptz;
  v_prueba timestamptz;
BEGIN
  SELECT (valor = 'true') INTO v_exigir FROM configuracion WHERE clave = 'exigir_suscripcion';
  IF v_exigir IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('acceso', true, 'estado', 'libre', 'dias_restantes', NULL, 'exigir', false);
  END IF;

  SELECT max(proximo_cobro) INTO v_pagado
  FROM suscripciones WHERE estado = 'activa' AND proximo_cobro > now();
  IF v_pagado IS NOT NULL THEN
    RETURN jsonb_build_object('acceso', true, 'estado', 'activa', 'exigir', true,
      'dias_restantes', ceil(extract(epoch FROM (v_pagado - now())) / 86400)::int);
  END IF;

  SELECT max(prueba_hasta) INTO v_prueba
  FROM suscripciones WHERE estado = 'prueba' AND prueba_hasta > now();
  IF v_prueba IS NOT NULL THEN
    RETURN jsonb_build_object('acceso', true, 'estado', 'prueba', 'exigir', true,
      'dias_restantes', ceil(extract(epoch FROM (v_prueba - now())) / 86400)::int);
  END IF;

  IF EXISTS (SELECT 1 FROM suscripciones WHERE estado IN ('activa', 'prueba', 'vencida')) THEN
    RETURN jsonb_build_object('acceso', false, 'estado', 'vencida', 'exigir', true, 'dias_restantes', 0);
  END IF;
  RETURN jsonb_build_object('acceso', false, 'estado', 'sin_suscripcion', 'exigir', true, 'dias_restantes', 0);
END;
$$;

CREATE OR REPLACE FUNCTION plataforma_activa()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((estado_plataforma() ->> 'acceso')::boolean, false);
$$;

-- ===== Prueba gratuita de 7 días =====
CREATE OR REPLACE FUNCTION iniciar_prueba(
  p_conjunto text, p_nit text, p_contacto text, p_email text, p_telefono text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_nit text := regexp_replace(trim(COALESCE(p_nit, '')), '[^0-9A-Za-z-]', '', 'g');
  v_email text := lower(trim(COALESCE(p_email, '')));
  v_conjunto text := trim(COALESCE(p_conjunto, ''));
  v_contacto text := trim(COALESCE(p_contacto, ''));
  v_sus suscripciones%ROWTYPE;
  v_fin timestamptz := now() + interval '7 days';
BEGIN
  IF char_length(v_conjunto) < 3 THEN RAISE EXCEPTION 'Escribe el nombre del conjunto'; END IF;
  IF char_length(v_contacto) < 3 THEN RAISE EXCEPTION 'Escribe el nombre del contacto'; END IF;
  IF char_length(v_nit) < 5 THEN RAISE EXCEPTION 'El NIT no es válido'; END IF;
  IF v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'El correo no es válido'; END IF;

  -- Una sola prueba por correo
  IF EXISTS (SELECT 1 FROM suscripciones WHERE lower(email) = v_email AND prueba_hasta IS NOT NULL) THEN
    RAISE EXCEPTION 'Este correo ya usó la prueba gratuita. Contrata un plan para continuar.';
  END IF;

  SELECT * INTO v_sus FROM suscripciones WHERE nit = v_nit;
  IF FOUND THEN
    -- Solo se puede reutilizar un registro que nunca avanzó (pago iniciado y no completado)
    IF v_sus.estado <> 'pendiente' OR v_sus.prueba_hasta IS NOT NULL THEN
      RAISE EXCEPTION 'Este NIT ya tiene una suscripción o ya usó la prueba gratuita.';
    END IF;
    UPDATE suscripciones
       SET estado = 'prueba', inicio = now(), prueba_hasta = v_fin,
           conjunto_nombre = v_conjunto, contacto_nombre = v_contacto, email = v_email,
           telefono = NULLIF(trim(COALESCE(p_telefono, '')), '')
     WHERE id = v_sus.id;
  ELSE
    INSERT INTO suscripciones (conjunto_nombre, nit, contacto_nombre, email, telefono, estado, inicio, prueba_hasta)
    VALUES (v_conjunto, v_nit, v_contacto, v_email, NULLIF(trim(COALESCE(p_telefono, '')), ''), 'prueba', now(), v_fin);
  END IF;

  RETURN jsonb_build_object('prueba_hasta', v_fin);
END;
$$;

-- ===== Aplicar el resultado de un pago (compartido por el simulador) =====
-- Misma lógica que la Edge Function wompi-webhook. NO se concede a anon.
CREATE OR REPLACE FUNCTION aplicar_pago(p_reference text, p_estado text, p_tx text, p_metodo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pago pagos%ROWTYPE;
  v_sus suscripciones%ROWTYPE;
  v_base timestamptz;
BEGIN
  SELECT * INTO v_pago FROM pagos WHERE reference = p_reference FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Referencia desconocida'; END IF;
  IF v_pago.estado = 'APPROVED' THEN RETURN; END IF; -- no se procesa dos veces

  UPDATE pagos SET estado = p_estado, wompi_transaction_id = p_tx, metodo_pago = p_metodo, updated_at = now()
   WHERE id = v_pago.id;

  IF p_estado = 'APPROVED' THEN
    SELECT * INTO v_sus FROM suscripciones WHERE id = v_pago.suscripcion_id FOR UPDATE;
    v_base := CASE WHEN v_sus.estado = 'activa' AND v_sus.proximo_cobro > now()
                   THEN v_sus.proximo_cobro ELSE now() END;
    UPDATE suscripciones
       SET estado = 'activa',
           inicio = COALESCE(inicio, now()),
           meses_pagados = meses_pagados + v_pago.meses,
           proximo_cobro = v_base + (v_pago.meses || ' months')::interval
     WHERE id = v_sus.id;
  END IF;
END;
$$;

-- ===== Pago SIMULADO: crear =====
-- Precios del documento (Tabla 1, FIN-01): 450.000 por mes y 2.000.000 de instalación (única vez).
CREATE OR REPLACE FUNCTION crear_pago_simulado(
  p_modo text, p_meses integer, p_nit text, p_email text,
  p_conjunto text DEFAULT NULL, p_contacto text DEFAULT NULL, p_telefono text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  c_mensual constant bigint := 450000;
  c_instalacion constant bigint := 2000000;
  v_nit text := regexp_replace(trim(COALESCE(p_nit, '')), '[^0-9A-Za-z-]', '', 'g');
  v_email text := lower(trim(COALESCE(p_email, '')));
  v_sus suscripciones%ROWTYPE;
  v_instalacion boolean := false;
  v_subtotal bigint;
  v_ref text;
BEGIN
  IF modo_pagos() <> 'simulado' THEN RAISE EXCEPTION 'El modo simulado está desactivado'; END IF;
  IF p_meses NOT IN (1, 3, 6, 12) THEN RAISE EXCEPTION 'Cantidad de meses no válida'; END IF;
  IF char_length(v_nit) < 5 THEN RAISE EXCEPTION 'El NIT no es válido'; END IF;
  IF v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'El correo no es válido'; END IF;

  SELECT * INTO v_sus FROM suscripciones WHERE nit = v_nit;

  IF p_modo = 'renovacion' THEN
    IF NOT FOUND OR lower(v_sus.email) <> v_email OR v_sus.estado NOT IN ('activa', 'vencida') THEN
      RAISE EXCEPTION 'No encontramos una suscripción con ese NIT y correo';
    END IF;
  ELSE
    IF char_length(trim(COALESCE(p_conjunto, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el nombre del conjunto'; END IF;
    IF char_length(trim(COALESCE(p_contacto, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el nombre del contacto'; END IF;
    IF FOUND AND v_sus.estado IN ('activa', 'vencida', 'cancelada') THEN
      RAISE EXCEPTION 'Este NIT ya tiene una suscripción. Usa la opción "Ya soy cliente".';
    END IF;
    IF NOT FOUND THEN
      INSERT INTO suscripciones (conjunto_nombre, nit, contacto_nombre, email, telefono)
      VALUES (trim(p_conjunto), v_nit, trim(p_contacto), v_email, NULLIF(trim(COALESCE(p_telefono, '')), ''))
      RETURNING * INTO v_sus;
    END IF;
    -- La cuota de instalación se cobra una sola vez
    v_instalacion := NOT EXISTS (
      SELECT 1 FROM pagos WHERE suscripcion_id = v_sus.id AND incluye_instalacion AND estado = 'APPROVED');
  END IF;

  v_subtotal := c_mensual * p_meses + CASE WHEN v_instalacion THEN c_instalacion ELSE 0 END;
  v_ref := 'COM-' || (extract(epoch FROM clock_timestamp()) * 1000)::bigint || '-' || upper(substr(md5(random()::text), 1, 8));

  INSERT INTO pagos (reference, suscripcion_id, tipo, meses, incluye_instalacion, subtotal_cop, iva_cop, total_cop)
  VALUES (v_ref, v_sus.id, CASE WHEN p_modo = 'renovacion' THEN 'renovacion' ELSE 'alta' END,
          p_meses, v_instalacion, v_subtotal, 0, v_subtotal);

  RETURN jsonb_build_object('reference', v_ref, 'total', v_subtotal);
END;
$$;

-- ===== Pago SIMULADO: resolver (aprobar / rechazar / error) =====
CREATE OR REPLACE FUNCTION simular_pago(p_reference text, p_resultado text, p_metodo text DEFAULT 'SIMULADO')
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_estado text;
BEGIN
  IF modo_pagos() <> 'simulado' THEN RAISE EXCEPTION 'El modo simulado está desactivado'; END IF;
  IF p_resultado NOT IN ('APPROVED', 'DECLINED', 'ERROR') THEN RAISE EXCEPTION 'Resultado no válido'; END IF;

  SELECT estado INTO v_estado FROM pagos WHERE reference = p_reference;
  IF v_estado IS NULL THEN RAISE EXCEPTION 'Referencia desconocida'; END IF;
  IF v_estado <> 'PENDING' THEN RAISE EXCEPTION 'Este pago ya fue procesado'; END IF;

  PERFORM aplicar_pago(p_reference, p_resultado, 'SIM-' || upper(substr(md5(random()::text), 1, 10)),
                       'SIMULADO ' || upper(left(COALESCE(p_metodo, ''), 20)));
  RETURN p_resultado;
END;
$$;

-- ===== Permisos =====
REVOKE ALL ON FUNCTION aplicar_pago(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION modo_pagos() FROM PUBLIC;
REVOKE ALL ON FUNCTION estado_plataforma() FROM PUBLIC;
REVOKE ALL ON FUNCTION plataforma_activa() FROM PUBLIC;
REVOKE ALL ON FUNCTION iniciar_prueba(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION crear_pago_simulado(text, integer, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION simular_pago(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION modo_pagos() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION estado_plataforma() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION plataforma_activa() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION iniciar_prueba(text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crear_pago_simulado(text, integer, text, text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION simular_pago(text, text, text) TO anon, authenticated;

-- ===== Bloqueo real: sin suscripción ni prueba vigente no se crean incidencias =====
DROP POLICY IF EXISTS "anon_insert_incidencias" ON incidencias;
CREATE POLICY "anon_insert_incidencias"
  ON incidencias FOR INSERT
  TO anon, authenticated
  WITH CHECK (
    foto_url IS NOT NULL AND length(trim(foto_url)) > 0
    AND plataforma_activa()
  );
