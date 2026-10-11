// Decodificación y descripción de códigos de falla (DTC).
//
// "Significado" = definición genérica SAE J2012 del código. Los textos se
// tradujeron de la tabla de python-OBD (obd/codes.py); solo se incluyen códigos
// genéricos verificados allí. Los códigos específicos del fabricante (P1xxx,
// P3xxx, U1xxx...) no tienen descripción pública verificable: se muestran como
// tales.
// "Posibles causas" = orientación general, NO un diagnóstico. Un código indica
// qué monitor de la ECU falló, no qué pieza está defectuosa.

export function decodeDtc(b1, b2) {
  if (b1 === 0 && b2 === 0) return null;
  const letter = 'PCBU'[b1 >> 6];
  const d1 = (b1 >> 4) & 0x03;
  const rest = ((b1 & 0x0f) << 8 | b2).toString(16).toUpperCase().padStart(3, '0');
  return `${letter}${d1}${rest}`;
}

// Respuesta CAN a servicios 03/07/0A: [0x43|0x47|0x4A, cantidad, b1, b2, ...]
export function parseDtcMessage(data) {
  let bytes = data.slice(1);
  if (bytes.length % 2 === 1 && bytes[0] * 2 === bytes.length - 1) bytes = bytes.slice(1);
  const codes = [];
  for (let i = 0; i + 1 < bytes.length; i += 2) {
    const c = decodeDtc(bytes[i], bytes[i + 1]);
    if (c) codes.push(c);
  }
  return codes;
}

const MEANING = {
  P0087: 'Presión del rail/sistema de combustible demasiado baja',
  P0088: 'Presión del rail/sistema de combustible demasiado alta',
  P0100: 'Circuito del sensor de caudal de aire (MAF)',
  P0101: 'Circuito del sensor MAF: rango/rendimiento',
  P0102: 'Circuito del sensor MAF: entrada baja',
  P0103: 'Circuito del sensor MAF: entrada alta',
  P0115: 'Circuito de temperatura del refrigerante',
  P0116: 'Circuito de temperatura del refrigerante: rango/rendimiento',
  P0117: 'Circuito de temperatura del refrigerante: señal baja',
  P0118: 'Circuito de temperatura del refrigerante: señal alta',
  P0190: 'Circuito del sensor de presión del rail de combustible',
  P0191: 'Sensor de presión del rail: rango/rendimiento',
  P0201: 'Circuito del inyector / abierto – cilindro 1',
  P0234: 'Condición de sobrepresión del turbo',
  P0299: 'Presión de turbo insuficiente (underboost)',
  P0335: 'Circuito del sensor de posición del cigüeñal "A"',
  P0340: 'Circuito del sensor de posición del árbol de levas "A"',
  P0380: 'Circuito de bujía de precalentamiento "A"',
  P0400: 'Flujo de recirculación de gases de escape (EGR)',
  P0401: 'Flujo de EGR insuficiente detectado',
  P0402: 'Flujo de EGR excesivo detectado',
  P0403: 'Circuito de control de EGR',
  P0404: 'Circuito de control de EGR: rango/rendimiento',
  P0470: 'Sensor de presión de escape',
  P0471: 'Sensor de presión de escape: rango/rendimiento',
  P0472: 'Sensor de presión de escape: señal baja',
  P0473: 'Sensor de presión de escape: señal alta',
  P0500: 'Sensor de velocidad del vehículo "A"',
  P0544: 'Circuito del sensor de temperatura de gases de escape',
  P0545: 'Circuito del sensor de temperatura de gases de escape: señal baja',
  P0546: 'Circuito del sensor de temperatura de gases de escape: señal alta',
  P0560: 'Voltaje del sistema',
  P0562: 'Voltaje del sistema bajo',
  P0563: 'Voltaje del sistema alto',
  P0606: 'Procesador de la ECM/PCM',
  P0670: 'Circuito de control del módulo de precalentamiento',
  P0700: 'Sistema de control de la transmisión (solicitud de MIL)',
  P0715: 'Circuito del sensor de velocidad de entrada/turbina "A"',
  P0720: 'Circuito del sensor de velocidad de salida',
  P0730: 'Relación de marcha incorrecta',
  P2002: 'Eficiencia del filtro de partículas por debajo del umbral',
  P2003: 'Eficiencia del filtro de partículas por debajo del umbral',
  P2031: 'Circuito del sensor de temperatura de gases de escape',
  P2032: 'Circuito del sensor de temperatura de gases de escape: señal baja',
  P2033: 'Circuito del sensor de temperatura de gases de escape: señal alta',
  P2080: 'Sensor de temperatura de gases de escape: rango/rendimiento',
  P2084: 'Sensor de temperatura de gases de escape: rango/rendimiento',
  P2201: 'Circuito del sensor de NOx: rango/rendimiento',
  P2263: 'Rendimiento del sistema de sobrealimentación (turbo)',
  U0001: 'Bus de comunicación CAN de alta velocidad',
  U0100: 'Pérdida de comunicación con ECM/PCM "A"',
  U0101: 'Pérdida de comunicación con el módulo de transmisión (TCM)',
  U0121: 'Pérdida de comunicación con el módulo ABS',
  U0140: 'Pérdida de comunicación con el módulo de carrocería (BCM)',
  U0155: 'Pérdida de comunicación con el cuadro de instrumentos',
};

const CAUSES = {
  P2002: ['Filtro con daño o fuga que reduce la diferencia de presión', 'Sensor de presión diferencial o sus mangueras defectuosos/sueltos', 'Fuga en el escape antes del DPF'],
  P0471: ['Sensor de presión de escape/diferencial defectuoso', 'Mangueras del sensor obstruidas, rotas o invertidas', 'Problema de conector o cableado'],
  P0401: ['Válvula EGR obstruida o pegada', 'Conductos o enfriador EGR con hollín', 'Problema de control eléctrico de la válvula'],
  P0299: ['Fuga en mangueras o intercooler', 'Actuador o geometría variable del turbo con problemas', 'Filtro de aire o escape restringidos'],
  P0087: ['Filtro de combustible restringido', 'Problema de bomba de alta presión o regulación', 'Fuga en el sistema de alta presión'],
  P0562: ['Batería débil o alternador con baja carga', 'Mala conexión de masa o bornes'],
  P0700: ['Indica que el módulo de transmisión guardó su propio código: hay que leer el TCM'],
};

// SAE J2012: P0, P2, P34–P39, B0, B3, C0, C3, U0 y U3 son genéricos;
// el resto (P1, P30–P33, B1, B2, C1, C2, U1, U2) es específico del fabricante.
export function classify(code) {
  const system = { P: 'Motor/transmisión', C: 'Chasis', B: 'Carrocería', U: 'Red/comunicación' }[code[0]];
  const d1 = code[1];
  let generic = d1 === '0' || d1 === '3';
  if (code[0] === 'P') generic = d1 === '0' || d1 === '2' || (d1 === '3' && /[4-9]/.test(code[2]));
  return { system, generic };
}

export function describe(code) {
  const { system, generic } = classify(code);
  const meaning = MEANING[code] ?? null;
  return {
    code,
    system,
    type: generic ? 'genérico SAE' : 'específico del fabricante',
    meaning: meaning ?? (generic
      ? 'Descripción no disponible en la base verificada de la app. Consultar SAE J2012.'
      : 'Código específico de Mercedes-Benz: su definición requiere documentación del fabricante (Xentry/WIS).'),
    possibleCauses: CAUSES[code] ?? [],
    note: 'Las posibles causas son orientativas. Confirmar con mediciones antes de reemplazar piezas.',
  };
}
