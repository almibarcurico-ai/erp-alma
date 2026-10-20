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
- **Usuarios dueño y secretaria**. La secretaria opera el día a día; solo el dueño ve los ingresos, decide las multas, elimina datos y administra usuarios. Todo queda en la bitácora.
- La **UF** se actualiza automáticamente desde mindicador.cl, y también se puede ingresar a mano.

> Por ahora los datos se guardan en el navegador (IndexedDB) y se sincronizan entre pestañas. Para usarla desde varios equipos a la vez, o para venderla como SaaS, falta conectar un backend con login real (por ejemplo, Supabase).
