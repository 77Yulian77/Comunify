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
