# erp-alma
almibarcurico-ai

## Alma Arriendos (`arriendos.html`)

Plataforma de gestión de arriendos para propiedades y centros comerciales. Se abre directamente en el navegador.

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

Los administradores de plataforma (Torre de Control HM) se cargan en `privado.admins_invitados` directamente en la base y quedan activos al registrarse con ese correo. La vista `torre_empresas` resume cada empresa cliente (plan, estado, unidades, ingreso mensual en UF).
