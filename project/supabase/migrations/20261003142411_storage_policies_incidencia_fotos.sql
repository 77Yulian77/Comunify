/*
# Storage policies for incidencia-fotos bucket

1. Security
- Allow public (anon) to upload photos to 'incidencia-fotos' bucket (residents report without login).
- Allow public to read photos (consultar.html needs to display evidence).
- Only authenticated admins can delete photos.
*/

-- Allow public to upload to incidencia-fotos
DROP POLICY IF EXISTS "anon_upload_fotos" ON storage.objects;
CREATE POLICY "anon_upload_fotos"
  ON storage.objects FOR INSERT
  TO anon, authenticated
  WITH CHECK (bucket_id = 'incidencia-fotos');

-- Allow public to read photos
DROP POLICY IF EXISTS "anon_read_fotos" ON storage.objects;
CREATE POLICY "anon_read_fotos"
  ON storage.objects FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'incidencia-fotos');

-- Allow authenticated admins to delete photos
DROP POLICY IF EXISTS "auth_delete_fotos" ON storage.objects;
CREATE POLICY "auth_delete_fotos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'incidencia-fotos');
