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

## Próximos pasos (en orden, cuando se necesiten)

1. **Propietarios y liquidaciones** — ficha de propietario (copropiedad con %), comisión de administración,
   liquidación mensual en PDF, portal del propietario. Es lo que hace a Qipo útil para corredoras que
   administran arriendos de terceros.
2. **Reajuste IPC y registro de reajustes** — fórmula, fuente, fecha, valor anterior/nuevo y aprobación.
3. **Fotos y documentos a Supabase Storage** — hoy las fotos van comprimidas dentro de la base; moverlas
   antes de crecer en número de empresas. URLs firmadas para documentos privados.
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
