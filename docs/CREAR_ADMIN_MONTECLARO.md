# Crear otra cuenta de administrador (conjunto Monteclaro)

El login de Comunify es solo correo + contraseña de Supabase Auth: **no hay que cambiar código** para una cuenta nueva. Cualquier usuario creado en Supabase puede entrar a `login.html`.

## Opción A (recomendada, sin SQL)
1. Supabase → **Authentication → Users → Add user → Create new user**.
2. Correo: `admin.monteclaro@comunify.app` (o el real del administrador) y una contraseña segura.
3. Marca **Auto Confirm User** y crea el usuario.
4. Entra a `https://comunify-uniminuto-2.netlify.app/login.html` con esos datos.

## Opción B (SQL)
Abre `supabase/scripts/crear_admin_monteclaro.sql`, cambia correo y contraseña y ejecútalo en **SQL Editor**. Ya incluye las columnas de tokens con `''` (evita el error "Database error querying schema") y la identidad `email`.

## Aplicar también la migración nueva
Para que "Eliminar definitivamente" funcione, ejecuta en el SQL Editor el contenido de
`supabase/migrations/20261105000001_eliminar_incidencias_definitivo.sql`.

## Roles: administrador de Comunify vs. cuenta de conjunto
- `role = admin` (en `app_metadata`): ve **Solicitudes** y **Generar QR**. Es la cuenta de Comunify (`admin@comunify.app`).
- Cualquier otra cuenta (ej. Monteclaro, `role = conjunto`): solo el panel de tickets. Sin Solicitudes ni Generar QR.
- Si creas la cuenta desde Authentication → Users no necesitas hacer nada: sin rol `admin` queda como cuenta de conjunto.
- Para convertir una cuenta en administrador de Comunify: SQL Editor →
  `UPDATE auth.users SET raw_app_meta_data = raw_app_meta_data || '{"role":"admin"}' WHERE email = 'tu@correo';`
  y esa persona debe cerrar sesión y volver a entrar.

## Separación por conjunto
- Cada ticket pertenece a un conjunto, que viene del QR/enlace de reporte (`reportar.html?conjunto=monteclaro`). Sin ese dato queda en Monteclaro.
- Cuenta de conjunto (ej. Monteclaro): ve, resuelve, archiva y elimina SOLO los tickets de su conjunto, y su pestaña Respaldo.
- Cuenta admin de Comunify (`role = admin`, conjunto `comunify`): ve SOLO los tickets de su conjunto, igual que las demás. Su rol extra es Solicitudes y Generar QR (elige para qué conjunto es cada QR).
- Para agregar otro conjunto con su cuenta: crea el usuario en Authentication y ejecuta `supabase/scripts/crear_conjunto_y_cuenta.sql` (cambia 3 valores).
- Después de ejecutar el SQL, cada persona debe cerrar sesión y volver a entrar.
- Los enlaces/QR sin conjunto mandan el ticket a `comunify`. Los QR de Monteclaro deben generarse con el conjunto «Monteclaro».
- El residente puede consultar su ticket por número aunque se haya eliminado «con copia de respaldo»; si se elimina definitivamente, ya no existe.

## Seguridad
- No dejes contraseñas en el repositorio (la migración antigua `create_admin_user.sql` tiene `Admin2026!`; cámbiala en Authentication → Users).
- Para quitar un acceso: Authentication → Users → ⋯ → Delete user.
