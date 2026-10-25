# Configurar los pagos con Wompi (paso a paso)

Todo el código ya está en el proyecto. Falta conectar tu cuenta de Wompi y publicar las funciones.

## 1. Cuenta y llaves de Wompi
1. Crea la cuenta de comercio en https://wompi.com y entra al dashboard en modo **Pruebas (sandbox)**.
2. En **Desarrolladores** copia: llave pública (`pub_test_...`), **secreto de integridad** y **secreto de eventos**.
   (Al pasar a producción se cambian por las llaves `prod`.)

## 2. Base de datos
En Supabase > SQL Editor, ejecuta en este orden:
1. `supabase/migrations/20261024000001_pagos_suscripciones.sql`
2. `supabase/migrations/20261024000002_demo_simulador_y_acceso.sql` (prueba gratis, simulador y bloqueo)

Tras la segunda migración el sitio queda en **modo simulado** y exige suscripción o prueba. Para pagos reales cambia el modo a `wompi` (ver `MODO_DEMO_Y_ACCESO.md`). Si solo quieres demostrar el sistema, no necesitas los pasos 1, 3 y 4.

## 3. Funciones del servidor (Supabase CLI)
```bash
supabase login
supabase link --project-ref TU_PROJECT_REF
supabase secrets set WOMPI_PUBLIC_KEY=pub_test_xxx WOMPI_INTEGRITY_SECRET=test_integrity_xxx WOMPI_EVENTS_SECRET=test_events_xxx SITE_URL=https://TU-SITIO.netlify.app
supabase functions deploy crear-pago
supabase functions deploy wompi-webhook --no-verify-jwt
```

## 4. URL de eventos en Wompi
En Wompi > Desarrolladores > URL de eventos (ambiente de pruebas) escribe:
`https://TU_PROJECT_REF.supabase.co/functions/v1/wompi-webhook`

## 5. Probar
1. Abre `/planes.html`, llena los datos y pulsa **Pagar con Wompi**.
2. Paga con los medios de prueba que entrega Wompi y confirma que `/pago-resultado.html` muestre «Pago aprobado».
3. En Supabase revisa las tablas `pagos` (estado APPROVED) y `suscripciones` (estado activa).

## 6. Pasar a producción
Cambia los secretos por los de producción (`supabase secrets set ...`), configura la URL de eventos del ambiente de producción y vuelve a probar con un pago real pequeño.

## IVA
Los precios son los del documento (sin IVA). Si el contador define que se cobra IVA, cambia `IVA` a `0.19` en `project/js/pagos.js` y en `supabase/functions/crear-pago/index.ts` (deben coincidir) y vuelve a desplegar.
