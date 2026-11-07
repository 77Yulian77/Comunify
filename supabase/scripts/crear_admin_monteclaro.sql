-- Crear un administrador nuevo (ej. Monteclaro) desde el SQL Editor de Supabase.
-- NO es una migración: se ejecuta a mano UNA vez, cambiando el correo y la contraseña.
-- Alternativa más simple: Authentication > Users > Add user > Create new user (marca "Auto Confirm User").

DO $$
DECLARE
  v_email text := 'admin.monteclaro@comunify.app';   -- <-- CAMBIA
  v_pass  text := 'CAMBIA-ESTA-CLAVE-123!';          -- <-- CAMBIA (mín. 8, mezcla letras/números)
  v_id    uuid := gen_random_uuid();
BEGIN
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
    RAISE NOTICE 'Ese correo ya existe: no se creó nada';
    RETURN;
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    created_at, updated_at, raw_app_meta_data, raw_user_meta_data, email_change_confirm_status,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, reauthentication_token, phone_change, phone_change_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    crypt(v_pass, gen_salt('bf')), now(), now(), now(),
    '{"provider":"email","providers":["email"],"role":"conjunto"}'::jsonb,
    '{"conjunto":"Monteclaro"}'::jsonb, 0,
    '', '', '', '', '', '', '', ''
  );

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at)
  VALUES (gen_random_uuid(), v_id,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
    'email', v_id::text, now(), now());
END $$;
