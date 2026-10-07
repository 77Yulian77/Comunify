/*
# Create Comunify Incidencias Schema

1. New Tables
- `incidencias`: Stores incident reports from residents of Conjunto Residencial Monteclaro P.H.
  - `id` (uuid, primary key)
  - `ticket_number` (text, unique, format TCK-2026-XXX, generated via sequence)
  - `descripcion` (text, not null) - incident description
  - `torre` (text, not null) - building A/B/C
  - `piso` (int, not null) - floor 1-10
  - `zona` (text, not null) - area: pasillo, parqueadero, ascensor, zonas_verdes, lobby
  - `foto_url` (text, nullable) - URL to uploaded evidence photo in storage
  - `residente_nombre` (text, nullable) - optional resident name
  - `estado` (text, not null, default 'Pendiente') - status: Pendiente, En Proceso, Resuelto
  - `created_at` (timestamptz, default now())

2. Security
- Enable RLS on `incidencias`.
- Public (anon) can INSERT new incidents and SELECT to look up tickets.
- Only authenticated admins can UPDATE estado and DELETE.

3. Notes
- Ticket numbers use a PostgreSQL sequence for uniqueness (TCK-2026-XXX).
- Photo evidence stored in Supabase Storage bucket 'incidencia-fotos'.
- No user_id foreign keys - this is a public reporting system.
*/

CREATE SEQUENCE IF NOT EXISTS incidencia_ticket_seq
  START WITH 1
  INCREMENT BY 1
  NO CYCLE;

CREATE TABLE IF NOT EXISTS incidencias (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_number text UNIQUE NOT NULL DEFAULT ('TCK-2026-' || lpad(nextval('incidencia_ticket_seq')::text, 3, '0')),
  descripcion text NOT NULL,
  torre text NOT NULL CHECK (torre IN ('A', 'B', 'C')),
  piso int NOT NULL CHECK (piso >= 1 AND piso <= 10),
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
