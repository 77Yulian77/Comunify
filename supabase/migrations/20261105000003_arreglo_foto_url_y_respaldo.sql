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
