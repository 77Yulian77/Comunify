/*
# Corrige el usuario administrador (error "Database error querying schema")

1. Propósito
- El usuario admin se creó con INSERT directo en auth.users y las columnas de tokens quedaron en NULL.
- Supabase Auth espera cadenas vacías, no NULL; con NULL el login falla.

2. Cambios
- Reemplaza NULL por '' en las columnas de tokens de admin@comunify.app.
- No modifica incidencias ni otros usuarios.
*/

UPDATE auth.users
SET
  confirmation_token         = COALESCE(confirmation_token, ''),
  recovery_token             = COALESCE(recovery_token, ''),
  email_change               = COALESCE(email_change, ''),
  email_change_token_new     = COALESCE(email_change_token_new, ''),
  email_change_token_current = COALESCE(email_change_token_current, ''),
  reauthentication_token     = COALESCE(reauthentication_token, ''),
  phone_change               = COALESCE(phone_change, ''),
  phone_change_token         = COALESCE(phone_change_token, '')
WHERE email = 'admin@comunify.app';
