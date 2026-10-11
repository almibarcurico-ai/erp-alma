// PIDs del servicio 01 (SAE J1979). Solo se incluyen fórmulas verificadas
// contra la implementación de referencia python-OBD (obd/commands.py,
// obd/decoders.py, obd/UnitsAndScaling.py). `d` son los bytes de datos que
// siguen al PID (A = d[0], B = d[1], ...).

const u16 = d => d[0] * 256 + d[1];

export const LIVE_PIDS = {
  0x04: { name: 'Carga calculada del motor', unit: '%', bytes: 1, decode: d => d[0] * 100 / 255 },
  0x05: { name: 'Temperatura del refrigerante', unit: '°C', bytes: 1, decode: d => d[0] - 40 },
  0x0B: { name: 'Presión absoluta del colector (MAP)', unit: 'kPa', bytes: 1, decode: d => d[0] },
  0x0C: { name: 'Régimen del motor', unit: 'rpm', bytes: 2, decode: d => u16(d) / 4 },
  0x0D: { name: 'Velocidad del vehículo', unit: 'km/h', bytes: 1, decode: d => d[0] },
  0x0F: { name: 'Temperatura del aire de admisión', unit: '°C', bytes: 1, decode: d => d[0] - 40 },
  0x10: { name: 'Caudal de aire (MAF)', unit: 'g/s', bytes: 2, decode: d => u16(d) / 100 },
  0x11: { name: 'Posición de mariposa', unit: '%', bytes: 1, decode: d => d[0] * 100 / 255 },
  0x1F: { name: 'Tiempo desde el arranque', unit: 's', bytes: 2, decode: d => u16(d) },
  0x21: { name: 'Distancia con MIL encendida', unit: 'km', bytes: 2, decode: d => u16(d) },
  0x23: { name: 'Presión del rail de combustible (manométrica)', unit: 'kPa', bytes: 2, decode: d => u16(d) * 10 },
  0x2C: { name: 'EGR comandada', unit: '%', bytes: 1, decode: d => d[0] * 100 / 255 },
  0x2F: { name: 'Nivel de combustible', unit: '%', bytes: 1, decode: d => d[0] * 100 / 255 },
  0x31: { name: 'Distancia desde borrado de códigos', unit: 'km', bytes: 2, decode: d => u16(d) },
  0x33: { name: 'Presión barométrica', unit: 'kPa', bytes: 1, decode: d => d[0] },
  0x3C: { name: 'Temperatura catalizador B1S1', unit: '°C', bytes: 2, decode: d => u16(d) / 10 - 40 },
  0x3E: { name: 'Temperatura catalizador B1S2', unit: '°C', bytes: 2, decode: d => u16(d) / 10 - 40 },
  0x42: { name: 'Voltaje del módulo de control', unit: 'V', bytes: 2, decode: d => u16(d) / 1000 },
  0x46: { name: 'Temperatura ambiente', unit: '°C', bytes: 1, decode: d => d[0] - 40 },
  0x49: { name: 'Posición del acelerador D', unit: '%', bytes: 1, decode: d => d[0] * 100 / 255 },
  0x4D: { name: 'Tiempo con MIL encendida', unit: 'min', bytes: 2, decode: d => u16(d) },
  0x4E: { name: 'Tiempo desde borrado de códigos', unit: 'min', bytes: 2, decode: d => u16(d) },
  0x5C: { name: 'Temperatura del aceite', unit: '°C', bytes: 1, decode: d => d[0] - 40 },
  0x5E: { name: 'Consumo de combustible', unit: 'L/h', bytes: 2, decode: d => u16(d) * 0.05 },
};

// Parámetros principales para la vista en vivo (si la ECU los soporta).
export const DEFAULT_LIVE = [0x0C, 0x05, 0x0D, 0x04, 0x0B, 0x10, 0x23, 0x42, 0x46, 0x5C];

// PIDs estándar relacionados con DPF y escape. Existen en SAE J1979, pero NO
// tenemos una fuente verificable de su estructura de bytes en este proyecto,
// así que se muestran como "soportado / no soportado" y bytes crudos, sin
// convertir a unidades. No se inventan fórmulas.
export const DPF_RAW_PIDS = {
  0x78: 'Temperatura de gases de escape (EGT) banco 1',
  0x79: 'Temperatura de gases de escape (EGT) banco 2',
  0x7A: 'Filtro de partículas (DPF) banco 1',
  0x7B: 'Filtro de partículas (DPF) banco 2',
  0x7C: 'Temperatura del DPF',
  0x8B: 'Postratamiento diésel (estado)',
};

// Servicio 01 PID 01: estado desde el borrado de códigos.
export function decodeStatus(d) {
  return {
    mil: Boolean(d[0] & 0x80),
    dtcCount: d[0] & 0x7f,
    ignition: d[1] & 0x08 ? 'compresión (diésel)' : 'chispa (gasolina)',
  };
}

// Bitmap de PIDs soportados (PIDs 00, 20, 40, ...). El bit más significativo
// del primer byte corresponde a base+1.
export function decodeSupported(base, d) {
  const out = [];
  for (let i = 0; i < 32; i++) {
    const byte = d[i >> 3];
    if (byte & (0x80 >> (i & 7))) out.push(base + i + 1);
  }
  return out;
}

export function decodePid(pid, d) {
  const def = LIVE_PIDS[pid];
  if (!def) return null;
  if (d.length < def.bytes) return null;
  return { pid, name: def.name, unit: def.unit, value: def.decode(d) };
}

export const hex = (n, w = 2) => n.toString(16).toUpperCase().padStart(w, '0');
