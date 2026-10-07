/*
# Create default admin user for Comunify

Creates an admin user in auth.users so the dashboard login works.
Email: admin@comunify.app
Password: Admin2026!
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'admin@comunify.app') THEN
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
      'admin@comunify.app',
      crypt('Admin2026!', gen_salt('bf')),
      now(),
      now(),
      now(),
      '{"role":"admin"}'::jsonb,
      '{}'::jsonb,
      0
    );
  END IF;
END $$;
