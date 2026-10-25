# Prueba gratis, pagos simulados y bloqueo de la plataforma

## Cómo funciona
| Situación | Qué pasa |
|---|---|
| Sin suscripción ni prueba | `reportar`, `consultar` y `dashboard` muestran un aviso de bloqueo con botones "Ver planes" y "Probar 7 días gratis". En la base de datos tampoco se pueden crear incidencias. |
| Prueba gratis (7 días) | Todo funciona y se ve un aviso con los días que quedan. Una sola prueba por NIT y por correo. |
| Prueba o suscripción vencida | Se bloquea de nuevo y se pregunta si quiere suscribirse ("Suscribirme" o "Ahora no"). Los reportes anteriores se conservan. |
| Suscripción pagada | Todo funciona hasta la fecha del próximo cobro. |

Las páginas que siempre quedan abiertas: inicio, planes, pago, login y políticas.

## Modo simulado vs. modo real
La pasarela se cambia con un valor en la tabla `configuracion` (SQL Editor de Supabase):

```sql
-- Demostración: pagos simulados (sin dinero real, sin cuenta de Wompi)
UPDATE configuracion SET valor = 'simulado' WHERE clave = 'modo_pagos';

-- Real: Wompi (requiere funciones desplegadas y llaves; ver CONFIGURAR_PAGOS_WOMPI.md)
UPDATE configuracion SET valor = 'wompi' WHERE clave = 'modo_pagos';
```

En modo simulado, "Pagar" lleva a `simulador-pago.html`: eliges PSE, tarjeta o Nequi y el resultado que quieres ver (aprobado, rechazado o error). Los datos que escribas ahí no se guardan ni se envían.

## Apagar o encender el bloqueo
```sql
UPDATE configuracion SET valor = 'false' WHERE clave = 'exigir_suscripcion'; -- plataforma libre
UPDATE configuracion SET valor = 'true'  WHERE clave = 'exigir_suscripcion'; -- exige suscripción o prueba
```

## Para la sustentación
1. Entra a `/planes.html` > **Prueba gratis** > llena los datos: la plataforma se habilita 7 días.
2. Para mostrar el bloqueo sin esperar 7 días, en el SQL Editor:
   `UPDATE suscripciones SET prueba_hasta = now() - interval '1 day' WHERE estado = 'prueba';`
   Al recargar `/reportar.html` aparece el aviso de bloqueo.
3. En **Conjunto nuevo** o **Ya soy cliente** paga con el simulador (aprobado) y la plataforma vuelve a abrirse.
4. Prueba un pago **rechazado** para mostrar que no se activa.

## Supuesto
Comunify atiende hoy un solo conjunto (piloto Monteclaro), así que el acceso es global. Con varios conjuntos habría que ligar cada incidencia a su suscripción.
