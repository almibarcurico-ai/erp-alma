# Pangoa: precuenta no se imprimía al aplicar descuento

**Fecha:** 13-sep-2026 · **Sistema:** POS Restoclick (RestoIA), proyecto Supabase `restoia-platform` (`gxjzwyickfrqxnhaajwv`), tenant Pangoa `816da88d-56a8-4d0d-81d3-48b1815515ea`.

## Síntoma

En Pangoa, al elegir un descuento en la pantalla de precuenta y tocar **Imprimir**, la precuenta no salía por la impresora de caja. Sin descuento sí imprimía.

## Cómo funciona la precuenta en el POS nuevo

1. El POS hace un solo `PATCH /rest/v1/orders` con `discount_type`, `discount_value`, `pricing_breakdown`, `subtotal`, `total` y `notes = 'PRECUENTA_REQUEST'`.
2. El trigger `trg_orders_precuenta` (AFTER UPDATE OF notes) ve el cambio a `PRECUENTA_REQUEST` y llama a `enqueue_print_job(order, 'precuenta')`.
3. Eso inserta en `print_jobs`; el print-agent local lo imprime y al terminar limpia `notes`.

## Causa raíz

El 01-sep-2026 se descontinuó el "Descuento Convenio 40% cocina" de Pangoa con la migración `pangoa_descontinuar_convenio`. Esa migración creó el trigger `trg_pangoa_guard_convenio` (BEFORE INSERT/UPDATE en `orders`), que lanza una excepción cuando el `pricing_breakdown` que llega contiene la palabra "convenio" y la orden no lo tenía antes.

El POS desplegado todavía tiene el botón/regla Convenio para Pangoa (la migración lo dice: "puente hasta que se despliegue el POS sin el botón"). Cuando el garzón lo elige, el POS envía un `pricing_breakdown` con la línea `Descuento Convenio 40% cocina`, y el guard rechaza **el UPDATE completo**, incluido `notes = 'PRECUENTA_REQUEST'`. Como la nota nunca se escribe, el trigger de precuenta nunca corre y no hay `print_jobs`. El POS queda sin imprimir.

Evidencia en los logs de Postgres (12 y 13 de septiembre, decenas de veces por servicio):

```
ERROR: El Descuento Convenio fue descontinuado (01-sep-2026). Ya no se aplica en Pangoa.
CONTEXT: PL/pgSQL function pangoa_guard_convenio_descontinuado() line 19 at RAISE
query: UPDATE "public"."orders" SET "discount_type" = ..., "discount_value" = ..., "notes" = ..., "pricing_breakdown" = ..., "subtotal" = ..., "total" = ...
```

Los intentos llegan en pares (aplicar descuento, luego Imprimir) y sólo imprime cuando el garzón vuelve a intentar con un descuento genérico (10 / 20 / 30 / 40 %), que no lleva la palabra "convenio".

## Solución aplicada

Migración `pangoa_convenio_no_bloquear_precuenta` (archivo `sql/20260913_pangoa_convenio_no_bloquear_precuenta.sql`), ya aplicada en producción:

- El guard deja de lanzar excepción. En su lugar **quita las líneas Convenio** de `pricing_breakdown.discountLines`, recalcula `totalDiscount`, `total`, `finalTotal` y `suggestedTip`, y si no queda ningún descuento automático deja `pricing_breakdown = NULL`.
- Recalcula `orders.total` = subtotal − descuento manual (porcentaje o monto) − descuentos automáticos que sigan vigentes.
- Registra el intento en `order_logs` con la acción `convenio_descontinuado_ignorado` para que administración vea cuántas veces se sigue tocando el botón.
- Sigue siendo fail-open: si algo falla dentro del guard, la fila pasa sin cambios.
- La definición anterior quedó respaldada en `public._bak_pangoa_guard_convenio_20260913` (con RLS habilitado). Para volver atrás basta ejecutar ese `definition`.

Resultado: el UPDATE se acepta, `notes` queda en `PRECUENTA_REQUEST`, se encola la precuenta y se imprime **sin** el descuento Convenio (que sigue descontinuado). Cualquier otro descuento (10 / 20 / 30 / 40 % o monto fijo) se imprime igual que antes.

Pruebas hechas en una transacción revertida sobre la orden 3423 de Pangoa:

| Caso | Resultado |
|---|---|
| Convenio + `PRECUENTA_REQUEST` | UPDATE aceptado, breakdown NULL, total 57.400, 1 `print_jobs` tipo precuenta con descuento 0, 1 fila en `order_logs` |
| Convenio + otra línea + 10 % manual | Se conserva la otra línea (1.000), total recalculado, breakdown coherente |
| UPDATE sin Convenio | Sin cambios, sin log |

## Pendiente (fuera de este repo)

- Quitar el botón/regla "Descuento Convenio" de Pangoa en el front-end del POS (repo `restoia-app`, deploy `app.restoclick.cl`). Mientras siga ahí, el garzón lo puede tocar; ahora simplemente se ignora y la precuenta sale sin ese descuento.
- Revisar la tabla `order_logs` (acción `convenio_descontinuado_ignorado`) para confirmar que los intentos bajan una vez retirado el botón.
