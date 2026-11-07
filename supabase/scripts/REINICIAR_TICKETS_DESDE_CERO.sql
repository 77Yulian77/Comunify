-- ⚠️ DESTRUCTIVO: borra TODOS los tickets y reinicia la numeración para que el próximo sea TCK-2026-001.
-- No se puede deshacer. Ejecútalo a mano en Supabase → SQL Editor, solo cuando quieras empezar de cero.
-- NO toca: cuentas de administrador, suscripciones/pagos/prueba gratuita, solicitudes de contacto, configuración.
-- Las fotos NO se borran con SQL: vacía el bucket a mano (Storage → incidencia-fotos → seleccionar todo → Delete).

TRUNCATE TABLE incidencias;
TRUNCATE TABLE incidencias_respaldo;          -- copias de tickets eliminados (la crea la migración 3)
ALTER SEQUENCE incidencia_ticket_seq RESTART WITH 1;

-- Comprobación: debe devolver 0 filas y el próximo número será TCK-2026-001
SELECT count(*) AS tickets_restantes FROM incidencias;
