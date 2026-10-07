/*
# Repair the Comunify administrator email identity

1. Purpose
- Repairs the administrator account created for Comunify so Supabase email/password login can find its email identity.

2. Data changes
- Adds the missing `email` provider identity for `admin@comunify.app` when it is absent.
- Does not delete or change incident reports.

3. Security
- The identity is linked only to the existing administrator user UUID.
- The password remains managed by Supabase Auth.
*/

DO $$
DECLARE
  admin_user_id uuid;
BEGIN
  SELECT id INTO admin_user_id
  FROM auth.users
  WHERE email = 'admin@comunify.app'
  LIMIT 1;

  IF admin_user_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM auth.identities
       WHERE user_id = admin_user_id
         AND provider = 'email'
     ) THEN
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      admin_user_id,
      jsonb_build_object(
        'sub', admin_user_id::text,
        'email', 'admin@comunify.app',
        'email_verified', true,
        'phone_verified', false
      ),
      'email',
      admin_user_id::text,
      now(),
      now()
    );
  END IF;
END $$;
