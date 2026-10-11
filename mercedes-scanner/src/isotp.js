// Interpreta las líneas que entrega el ELM327 con cabeceras activas (ATH1) en
// protocolos CAN ISO 15765-4 y reensambla los mensajes multi-trama (ISO-TP).
//   11 bits: "7E8 06 41 00 BE 3F A8 13"
//   29 bits: "18 DA F1 10 06 41 00 BE 3F A8 13"
// Devuelve un mensaje por ECU: { ecu: '7E8', data: [0x41, 0x00, ...] }.

const HEX2 = /^[0-9A-F]{2}$/i;

function parseLine(line) {
  const t = line.trim().split(/\s+/);
  if (/^[0-9A-F]{3}$/i.test(t[0])) {
    return { ecu: t[0].toUpperCase(), bytes: t.slice(1) };
  }
  if (t.length >= 5 && t.slice(0, 4).every(x => HEX2.test(x))) {
    return { ecu: t.slice(0, 4).join('').toUpperCase(), bytes: t.slice(4) };
  }
  return null;
}

export function parseCanResponse(lines) {
  const frames = new Map();
  for (const line of lines) {
    const p = parseLine(line);
    if (!p || !p.bytes.every(b => HEX2.test(b))) continue;
    const bytes = p.bytes.map(b => parseInt(b, 16));
    if (!frames.has(p.ecu)) frames.set(p.ecu, []);
    frames.get(p.ecu).push(bytes);
  }

  const messages = [];
  for (const [ecu, list] of frames) {
    let current = null;
    for (const f of list) {
      const type = f[0] >> 4;
      if (type === 0) {
        const len = f[0] & 0x0f;
        messages.push({ ecu, data: f.slice(1, 1 + len) });
      } else if (type === 1) {
        const len = ((f[0] & 0x0f) << 8) | f[1];
        current = { ecu, len, data: f.slice(2), next: 1 };
      } else if (type === 2 && current) {
        const seq = f[0] & 0x0f;
        if (seq !== current.next) { current = null; continue; } // trama perdida: descartar mensaje
        current.data.push(...f.slice(1));
        current.next = (current.next + 1) & 0x0f;
        if (current.data.length >= current.len) {
          messages.push({ ecu, data: current.data.slice(0, current.len) });
          current = null;
        }
      }
    }
  }
  return messages;
}

export function ecuLabel(ecu) {
  // Direcciones de respuesta físicas estándar de ISO 15765-4 (7E8–7EF).
  // Qué módulo corresponde a cada una lo define el fabricante; 7E8 suele ser
  // el motor, pero se confirma con el servicio 09 PID 0A (nombre de la ECU).
  const std = { '7E8': 'ECU #1 (7E8)', '7E9': 'ECU #2 (7E9)', '7EA': 'ECU #3 (7EA)', '7EB': 'ECU #4 (7EB)' };
  return std[ecu] ?? `ECU ${ecu}`;
}
