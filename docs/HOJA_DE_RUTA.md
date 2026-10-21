# Hoja de ruta — Qipo

Referencia: el "prompt maestro" de plataforma SaaS inmobiliaria multiempresa. Se usa como **ruta**, no como
tarea única: cada módulo se construye cuando un cliente real lo necesita, sobre la base actual
(Supabase + RLS multiempresa + Vercel) y sin rehacer lo que ya funciona.

Estados: ✅ hecho · 🟡 parcial · ⬜ pendiente

## Hecho hoy (arriendos.qipo.cl)

| Área | Estado | Qué hay |
|---|---|---|
| Multiempresa | 🟡 | empresas, miembros, invitaciones, RLS por empresa, planes con límite de unidades validado en la base |
| Superadmin (Torre de Control HM) | 🟡 | vista `torre_empresas` y `admins_plataforma` en la base; falta la interfaz |
| Roles | 🟡 | dueño y secretaria |
| Propiedades | 🟡 | propiedades y unidades (locales), mapa, fotos, servicios (luz, agua, gastos comunes), inventario con fotos |
| Arriendos y cobranza | 🟡 | contratos UF/CLP, día de pago, pagos, abonos, multas opcionales, IVA opcional, reajuste % cada N meses |
| Documentos | 🟡 | contrato, anexos e inventario generados en HTML/Word/PDF |
| Interesados | 🟡 | lista básica y ficha compartible de desocupadas |
| Pagos del SaaS | ⬜ | tabla `cobros_suscripcion`, sin pasarela |
| Propietarios y liquidaciones | 🟡 | ficha con datos bancarios (solo dueño), comisión % + IVA, liquidación mensual en PDF (inmutable: se paga o se anula), Excel |
| Planes | ✅ | precios en pesos, límites de unidades y usuarios, funciones por plan validadas en la base (`privado.plan_permite`) |
| Fotos | ✅ | en Supabase Storage (bucket `fotos`, carpeta por empresa) |

## Planes (precios netos, + IVA; anual = 10 meses)

| | Propietario | Corredor | Profesional | Empresa |
|---|---|---|---|---|
| Mensual | $14.900 | $39.900 | $79.900 | $149.900 |
| Unidades | 10 | 50 | 200 | 600 |
| Usuarios | 2 | 3 | 8 | 20 |
| Cobranza, contratos, mapa, multas, abonos, reajustes, IVA, inventario | ✓ | ✓ | ✓ | ✓ |
| Propietarios y liquidaciones | — | ✓ | ✓ | ✓ |
| Exportar a Excel | — | — | ✓ | ✓ |
| Soporte prioritario y migración de datos | — | — | — | ✓ |

Prueba de 14 días con todo habilitado. Más de 600 unidades: Corporativo a convenir (`suscripciones.precio_clp_pactado`).
Los planes se cambian en la tabla `planes` sin tocar código.

## Próximos pasos (en orden, cuando se necesiten)

1. **Propietarios (siguiente paso)** — copropiedad con %, portal del propietario para ver sus liquidaciones.
2. **Reajuste IPC y registro de reajustes** — fórmula, fuente, fecha, valor anterior/nuevo y aprobación.
3. **Documentos a Supabase Storage** — URLs firmadas para documentos privados; borrar del bucket las fotos que se quitan.
4. **Roles granulares** — corredor, cobranza, contador, propietario y arrendatario externos.
5. **Pruebas en el repo y CI** — aislamiento entre empresas, cálculos de cobro, abonos, reajustes.
6. **Mantenciones** — solicitudes con fotos, presupuesto, aprobación del propietario y quién asume el gasto.
7. **CRM y agenda** — embudo kanban, actividades, visitas.
8. **Sitio web por empresa** — buscador público, SEO, leads al CRM. Aquí conviene pasar a Next.js
   (renderizado en servidor), construyendo la app nueva en paralelo sobre el mismo Supabase.
9. **Cobro del SaaS** — integrar Flow / Mercado Pago / Transbank tras verificar condiciones; webhooks idempotentes.
10. **Corretaje de venta y comisiones repartidas**, automatizaciones, portales externos (solo vías autorizadas).

## Reglas que se mantienen

- Toda tabla de empresa lleva `empresa_id` y política RLS; los límites del plan se validan en la base, no solo en pantalla.
- Ninguna integración se declara activa sin verificar su documentación y credenciales.
- Los cambios de esquema van como migraciones versionadas en `supabase/migrations/`.
