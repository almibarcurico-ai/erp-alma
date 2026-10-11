# Escáner OBD-II de solo lectura · Mercedes-Benz GLA (X156)

App web local para diagnosticar un Mercedes-Benz GLA diésel 2017 (X156) desde un **Mac** con un **adaptador OBD2 USB** (ELM327 o STN/OBDLink).
Es independiente del ERP de este repositorio y no lo modifica.

> **Solo lectura.** La app no borra códigos ni reinicia adaptaciones. Tampoco hace regeneraciones forzadas, codificación ni pruebas de actuadores. No determina si el vehículo es seguro para conducir.

## Uso en el Mac

1. Requisitos: **Chrome o Edge**. Safari no es compatible con Web Serial.
2. Abre la Terminal dentro de la carpeta `mercedes-scanner/` y ejecuta:
   ```bash
   python3 -m http.server 8080
   ```
3. Abre `http://localhost:8080`. Web Serial solo funciona en `localhost` o en `https`, no si abres el archivo con doble clic.
4. Prueba primero con **Modo: Simulación**. Después elige **Adaptador USB real**, conecta y selecciona el puerto en el diálogo de Chrome.
5. Pon el contacto en marcha (motor encendido o apagado) y pulsa **Leer diagnóstico completo**.

### Identificar el adaptador USB

Con el adaptador conectado al Mac:

- **Menú Apple → Acerca de este Mac → Más información → Informe del sistema → USB**. Anota el fabricante, el *Vendor ID* y el *Product ID*.
- En la Terminal, `ls /dev/cu.*` debe mostrar un puerto nuevo (`cu.usbserial-…` o `cu.wchusbserial…`). Si no aparece, falta el driver del chip USB-serie. Muchos clones usan CH340/CH341 o PL2303; los adaptadores FTDI funcionan sin instalar nada.
- La app también muestra el VID/PID, la respuesta a `ATI` y si el chip es STN (`STI`).

La velocidad por defecto es 38400 baud, la habitual de los ELM327 USB. Algunos adaptadores (por ejemplo OBDLink) usan 115200.

## Compatibilidad real

| Función | ELM327 / clon | STN (OBDLink SX/EX) | Interfaz Mercedes (C4/C5/C6 + Xentry) |
|---|---|---|---|
| Códigos OBD-II genéricos (03/07/0A), freeze frame, datos SAE | Sí, con limitaciones en clones | Sí | Sí |
| VIN (09 02) | Si la ECU lo entrega | Igual | Sí |
| DTC propios de cada módulo Mercedes | No (sin datos del fabricante) | No (sin datos del fabricante) | Sí |
| Hollín/cenizas DPF, distancia desde regeneración | No disponible | No disponible | Sí |
| TCU, marcha y señales de paletas | No disponible | No disponible | Sí |

Ningún ELM327 permite por sí solo un diagnóstico Mercedes completo. El hardware puede llegar físicamente a otros módulos, pero los identificadores de datos (DIDs UDS) de Mercedes no son públicos. Muchos clones dicen ser "v1.5" o "v2.1" aunque no lo son.

## Qué hace (etapas)

1. **Conexión**: abre el puerto USB, inicializa el adaptador (eco, cabeceras, protocolo automático), lo identifica y lee el voltaje en el pin 16.
2. **OBD-II genérico (SAE J1979)**, solo en CAN ISO 15765-4:
   - VIN (09 02), nombre y calibración de cada ECU (09 0A / 09 04).
   - Estado: MIL y cantidad de códigos (01 01).
   - Códigos **confirmados** (03), **pendientes** (07) y **permanentes** (0A), por ECU.
   - **Freeze frame** (02).
   - **Datos en vivo**: rpm, refrigerante, velocidad, carga, MAP, MAF, presión del rail, voltaje, temperatura ambiente y del aceite. Se leen solo si la ECU los declara.
   - **Exportación** en JSON y texto con códigos originales, fecha, VIN y datos.
3. **Mercedes**: la estructura está lista, pero **sin parámetros cargados**. Cada parámetro de DPF y transmisión aparece como "No disponible" con el motivo.

### DPF

- Los PIDs SAE 78, 79, 7A, 7B, 7C y 8B, relacionados con EGT, DPF y postratamiento, se consultan **solo si la ECU los declara**. Se muestran como **bytes crudos**, porque la app no tiene una fuente verificada de su estructura y no inventa fórmulas.
- Presión diferencial, carga de hollín, cenizas, estado de regeneración y distancia desde la última regeneración: **No disponible**, porque requieren DIDs Mercedes.
- La interfaz distingue los valores **medidos** (sensor) de las **estimaciones** de la ECU.

### Transmisión y paletas

Si el TCU responde a OBD-II genérico (dirección 7E9 u otra), sus códigos de emisiones aparecen en la tabla de códigos. Los códigos propios del TCU, la marcha, la temperatura del aceite y las señales de paletas requieren diagnóstico Mercedes: SD Connect C4/C5/C6 con Xentry, o software J2534 con cobertura Mercedes verificada para la serie 156.

## Seguridad

- **Lista blanca** (`src/safety.js`): solo se permiten servicios OBD-II de lectura (01, 02, 03, 07, 09, 0A) y comandos AT/ST que configuran el propio adaptador. Se bloquean el modo 04 (borrar), el 08 y todo UDS (10, 11, 14, 22, 27, 2E, 2F, 31, 34…), además de `ATSH`, `ATMA` y otros. Un comando bloqueado nunca llega al adaptador.
- **Frecuencia limitada**: 120 ms mínimo entre comandos, una sola consulta a la vez, timeout de 5 s y datos en vivo a ~1 Hz.
- **Desconexiones**: si se desconecta el USB, se cancela la consulta en curso, se detiene la lectura en vivo y se avisa en pantalla.
- **Registro de depuración** sin VIN: las respuestas a 09 02 y cualquier texto con forma de VIN se ocultan.
- **Simulación separada**: banner morado permanente, transporte distinto e informe marcado como "DATOS SIMULADOS".

## Pruebas

```bash
npm test     # node --test, sin dependencias
```

### Validación

| Ítem | Simulación / pruebas automáticas | Requiere vehículo real |
|---|---|---|
| Lista blanca y bloqueo de comandos | ✅ | — |
| Reensamblado ISO-TP (VIN multi-trama, 2 ECU, trama perdida, 29 bits) | ✅ | Confirmar con el formato que entregue tu adaptador |
| Decodificación DTC, PIDs, freeze frame | ✅ (fórmulas comparadas con python-OBD) | Comparar con otra herramienta |
| Timeout, desconexión y frecuencia limitada | ✅ | Desconectar el cable durante una lectura |
| Interfaz completa (Chromium, modo simulación) | ✅ | — |
| Web Serial con el adaptador USB en macOS | ❌ no probado | **Sí** |
| Protocolo real del X156, ECUs que responden, VIN | ❌ | **Sí** |
| PIDs DPF genéricos declarados por la ECU | ❌ | **Sí** |
| Parámetros Mercedes (DPF detallado, TCU, paletas) | No implementado (sin fuente verificable) | Requiere hardware o datos Mercedes |

## Fuentes

- SAE J1979 / J2012: definiciones de servicios, PIDs y DTC genéricos. Las fórmulas y descripciones se contrastaron con [python-OBD](https://github.com/brendan-w/python-OBD) (`obd/commands.py`, `obd/decoders.py`, `obd/UnitsAndScaling.py`, `obd/codes.py`).
- Hoja de datos ELM327 (Elm Electronics): comandos AT y mensajes de error.
- ISO 15765-2 (ISO-TP): formato de tramas simples, primera trama y consecutivas.
