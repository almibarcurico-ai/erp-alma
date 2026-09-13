# Pangoa: precuenta no se imprimía al aplicar descuento

**Fecha:** 13-sep-2026 · **Sistema:** POS Restoclick (RestoIA), proyecto Supabase `restoia-platform` (`gxjzwyickfrqxnhaajwv`), tenant Pangoa `816da88d-56a8-4d0d-81d3-48b1815515ea`.

## Síntoma

En Pangoa, al elegir un descuento en la pantalla de precuenta y tocar **Imprimir**, la precuenta no salía por la impresora de caja. Con los descuentos genéricos (10 / 20 / 30 / 40 %) sí imprimía; fallaba al elegir el **Descuento Convenio**.

## Cómo funciona la precuenta en el POS nuevo

1. El POS hace un solo `PATCH /rest/v1/orders` con `discount_type`, `discount_value`, `pricing_breakdown`, `subtotal`, `total` y `notes = 'PRECUENTA_REQUEST'`.
2. El trigger `trg_orders_precuenta` (AFTER UPDATE OF notes) ve el cambio a `PRECUENTA_REQUEST` y llama a `enqueue_print_job(order, 'precuenta')`.
3. Eso inserta en `print_jobs`; el print-agent local lo imprime y al terminar limpia `notes`.

## Causa raíz

El 01-sep-2026 se descontinuó el "Descuento Convenio 40% cocina" de Pangoa con la migración `pangoa_descontinuar_convenio`. Esa migración creó el trigger `trg_pangoa_guard_convenio` (BEFORE INSERT/UPDATE en `orders`), que lanza una excepción cuando el `pricing_breakdown` que llega contiene la palabra "convenio" y la orden no lo tenía antes.

El POS desplegado todavía tiene el botón Convenio para Pangoa (la migración lo dice: "puente hasta que se despliegue el POS sin el botón"). Cuando el garzón lo elige, el POS envía un `pricing_breakdown` con la línea `Descuento Convenio 40% cocina`, y el guard rechaza **el UPDATE completo**, incluido `notes = 'PRECUENTA_REQUEST'`. Como la nota nunca se escribe, el trigger de precuenta nunca corre y no hay `print_jobs`.

Evidencia en los logs de Postgres (12 y 13 de septiembre, decenas de veces por servicio):

```
ERROR: El Descuento Convenio fue descontinuado (01-sep-2026). Ya no se aplica en Pangoa.
CONTEXT: PL/pgSQL function pangoa_guard_convenio_descontinuado() line 19 at RAISE
query: UPDATE "public"."orders" SET "discount_type" = ..., "discount_value" = ..., "notes" = ..., "pricing_breakdown" = ..., "subtotal" = ..., "total" = ...
```

Los intentos llegan en pares (aplicar descuento, luego Imprimir) y sólo imprime cuando el garzón vuelve a intentar con un descuento genérico.

## Solución aplicada

Migración `pangoa_convenio_precuenta_y_cierre` (archivo `sql/20260913_pangoa_convenio_no_bloquear_precuenta.sql`), aplicada en producción. El guard sigue impidiendo que el Convenio se aplique, pero ya no deja la precuenta sin imprimir:

| Update que llega con Convenio | Antes | Ahora |
|---|---|---|
| Pedido de precuenta (`notes = 'PRECUENTA_REQUEST'`) | Excepción, nada se imprime | Se quitan las líneas Convenio del breakdown, se recalculan totales, se registra en `order_logs` (`convenio_descontinuado_ignorado`) y **la precuenta se imprime sin el Convenio** |
| Aplicar el descuento (sin precuenta) o cerrar una mesa que nunca pasó por precuenta | Excepción | Excepción (igual), con un hint más claro: "Quite el Descuento Convenio y use otro descuento" |
| Cierre de una mesa que ya pasó por una precuenta con Convenio ignorado | — | No se bloquea (el pago ya está insertado; bloquear generaría pagos duplicados). Si el total cobrado es menor de lo que explican los descuentos registrados, el Convenio cobrado queda **registrado como descuento manual `monto`** y se anota en `order_logs` (`convenio_cobrado_descontinuado`) |

Sigue siendo fail-open: si algo falla dentro del guard, la fila pasa sin cambios. La definición original quedó respaldada en `public._bak_pangoa_guard_convenio_20260913` (con RLS habilitado). Para volver atrás basta ejecutar ese `definition`.

### Pruebas (transacción revertida, sobre órdenes abiertas de Pangoa)

| Caso | Resultado |
|---|---|
| Aplicar Convenio sin precuenta | Excepción, orden sin cambios |
| Convenio + `PRECUENTA_REQUEST` | UPDATE aceptado, breakdown NULL, total completo, 1 `print_jobs` precuenta con descuento 0, 1 log |
| Cierre de esa orden con total bajo | Cierre aceptado, `discount_type = monto` por la diferencia, 1 log `convenio_cobrado_descontinuado` |
| Cierre reenviando el breakdown con Convenio | Breakdown limpiado y diferencia registrada como monto |
| Cierre de una orden nunca marcada, con total bajo | Sin cambios (no se toca) |
| Cierre de una orden nunca marcada, con Convenio en el breakdown | Excepción (igual que antes) |

### Incidente durante la ventana intermedia

Entre las 17:16 y las 17:30 UTC del 13-sep estuvo activa una primera versión del guard que sólo limpiaba el Convenio (sin bloquear el paso de "aplicar descuento"). En esa ventana la orden **3425** (mesa 22) se cerró cobrando el total con Convenio (subtotal 38.600, total 27.880, pago débito 31.740 con 3.860 de propina) sin descuento registrado. La migración corrige ese registro: `discount_type = monto`, `discount_value = 10.720`, con nota en `order_logs`. El cobro al cliente no cambia; sólo queda explicado en reportes.

## Pendiente (fuera de este repo)

- Quitar el botón "Descuento Convenio" de Pangoa en el front-end del POS (repo `restoia-app`, deploy `app.restoclick.cl`). Mientras siga ahí, el garzón verá el aviso al tocarlo y la precuenta saldrá sin ese descuento.
- Revisar `order_logs` (acciones `convenio_descontinuado_ignorado` y `convenio_cobrado_descontinuado`) para confirmar que los intentos bajan una vez retirado el botón, y para detectar cobros con Convenio hechos desde la pantalla del POS.
