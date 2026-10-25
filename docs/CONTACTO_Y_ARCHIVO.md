# Página principal, solicitudes de contacto y archivo de tickets

## 1. Base de datos (SQL Editor de Supabase, en este orden)
1. `supabase/migrations/20261025000001_archivar_incidencias.sql` (archivar tickets)
2. `supabase/migrations/20261025000002_solicitudes_contacto.sql` (formulario "Regístrate y te contactamos")

Ejecuta la migración 1 ANTES de publicar el código nuevo: el panel usa la columna `archivada` y sin ella no carga.

## 2. Archivar tickets (en vez de eliminar)
- En el panel, un ticket **Resuelto** tiene el botón **Archivar**; también está **Archivar resueltos** para hacerlo en masa.
- Los archivados salen de la pestaña **Activos**, pero no se borra nada: ticket y foto se conservan.
- La pestaña **Archivados** los lista y permite **Restaurar** cada uno al panel.
- Un ticket archivado se sigue encontrando en **Consultar ticket** con su número.
- La base de datos solo permite archivar tickets en estado Resuelto.

## 3. Solicitudes "Regístrate y nosotros te contactamos"
El formulario está en la página principal (`#contacto`). Cada solicitud:
1. Se guarda en la tabla `solicitudes_contacto` (máximo 3 por correo cada 24 horas, con campo trampa contra bots).
2. Se ve en el panel del administrador: botón **Solicitudes** (`solicitudes.html`), donde se marca como contactada.
3. **Opcional:** llega por correo al equipo y la persona recibe una confirmación. Para eso:
   ```bash
   # cuenta gratuita en https://resend.com y una API key
   npx supabase secrets set RESEND_API_KEY=re_xxx CONTACT_EMAIL=correo-del-equipo@gmail.com
   npx supabase functions deploy notificar-contacto
   ```
   Con el remitente de pruebas de Resend (`onboarding@resend.dev`) solo se entregan correos a tu propio correo registrado en Resend; para escribirle a cualquier persona hay que verificar un dominio y definir `MAIL_FROM`.

Si no configuras el correo, todo sigue funcionando: la solicitud queda guardada y visible en **Solicitudes**.
