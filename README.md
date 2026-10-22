# erp-alma
almibarcurico-ai

## Qipo Arriendos (`arriendos/`)

Plataforma de gestión de arriendos para propiedades y centros comerciales. Es una sola página (`arriendos/index.html`) publicada en Vercel en el proyecto `qipo-arriendos` (directorio raíz `arriendos`).

- **Mapa interactivo** (mapa/satélite) con todas las propiedades y locales. El color indica el estado de cobro (atrasado, vence hoy, por vencer, pendiente, pagado, desocupada). Al pasar el mouse se ven los datos generales y al hacer clic se abre la ficha.
- **Ficha completa** con los datos de la propiedad, del arrendatario y del arriendo (fechas, día de pago, renta en UF o CLP, garantía), además de fotos, pagos y documentos.
- **Multas automáticas** según el contrato (por día, fija o porcentual, con días de gracia y tope). Solo se cobran si el dueño las activa, y el dueño puede condonarlas.
- **Cobranza** con registro de pagos y avisos por WhatsApp o correo usando plantillas (recordatorio, atraso, pago recibido, término de contrato).
- **Desocupadas**: se envía la ficha a un interesado por WhatsApp o correo, se comparten las fotos desde el celular o se genera una ficha en PDF. Cada envío queda registrado.
- **Contratos y anexos**: contrato habitacional y comercial, anexos de renta, de prórroga y libre, acta de término, aviso de no renovación, carta de cobranza y acta de entrega. Se pueden editar e imprimir en PDF o descargar en Word.
- **Panel del dueño**: ingresos del mes en tiempo real, morosidad, ocupación, ingresos de los últimos 6 meses y alertas.
- **Cuentas en la nube (Supabase)**: cada empresa cliente se registra sola con 14 días de prueba y ve solo sus datos. El dueño invita a la secretaria por correo. Los cambios se ven en tiempo real en todos los equipos. La secretaria opera el día a día; solo el dueño ve los ingresos, decide las multas, elimina datos y administra usuarios. Todo queda en la bitácora.
- La **UF** se actualiza automáticamente desde mindicador.cl, y también se puede ingresar a mano.

### Base de datos

Proyecto Supabase `qipo-arriendos`. Las migraciones están en `supabase/migrations/`:

| Migración | Estado |
|---|---|
| `20261020000000_esquema_inicial.sql` | aplicada |
| `20261020010000_funciones_privadas.sql` | aplicada |
| `20261020020000_optimizar_politicas.sql` | **pendiente**: aplicar desde el editor SQL de Supabase |
| `20261020030000_registro_e_invitaciones.sql` | aplicada |
| `20261021000000_servicios_unidades.sql` | aplicada |
| `20261021010000_iva_opcional.sql` | aplicada |
| `20261021020000_inventario_unidades.sql` | aplicada |
| `20261021030000_abonos.sql` | aplicada |
| `20261021040000_reajuste.sql` | aplicada |
| `20261022000000_fotos_storage.sql` | aplicada |
| `20261022010000_planes_propietarios_liquidaciones.sql` | aplicada |
| `20261022020000_search_path_funciones.sql` | aplicada |
| `20261022030000_pagina_web.sql` | aplicada |
| `20261022040000_web_arrendadas.sql` | aplicada |
| `20261022050000_web_logo.sql` | aplicada |
| `20261022060000_acceso_soporte.sql` | aplicada |
| `20261023000000_reajustes_ipc_uf.sql` | aplicada |

Los administradores de plataforma (Torre de Control HM) se cargan en `privado.admins_invitados` directamente en la base y quedan activos al registrarse con ese correo. La vista `torre_empresas` resume cada empresa cliente (plan, estado, unidades, ingreso mensual en UF).
