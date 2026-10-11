// Lista blanca de comandos. Todo lo que no esté aquí se bloquea ANTES de llegar
// al adaptador. La app es de solo lectura: nunca borra códigos (modo 04),
// nunca ejecuta servicios UDS de escritura, rutinas, actuadores ni codificación.

// Comandos AT del ELM327/STN permitidos. Solo configuran el adaptador o leen
// información del propio adaptador; ninguno se transmite al vehículo.
const AT_ALLOWED = [
  /^ATZ$/,          // reset del adaptador
  /^ATWS$/,         // reinicio en caliente del adaptador
  /^ATD$/,          // valores por defecto del adaptador
  /^ATE[01]$/,      // eco
  /^ATL[01]$/,      // salto de línea
  /^ATS[01]$/,      // espacios
  /^ATH[01]$/,      // mostrar cabeceras CAN
  /^ATSP0$/,        // protocolo automático
  /^ATDPN?$/,       // describir protocolo
  /^ATRV$/,         // voltaje medido por el adaptador en el pin 16
  /^ATI$/,          // identificación del chip
  /^AT@1$/,         // descripción del dispositivo
  /^ATAT[012]$/,    // temporización adaptativa
  /^ATST[0-9A-F]{2}$/, // timeout de respuesta
  /^ATCAF1$/,       // formateo automático CAN (por defecto)
  /^STI$/,          // identificación chip STN (OBDLink)
  /^STDI$/,         // descripción hardware STN
];

// Servicios OBD-II (SAE J1979) de solo lectura permitidos:
// 01 datos actuales, 02 freeze frame, 03 códigos confirmados,
// 07 códigos pendientes, 09 información del vehículo, 0A códigos permanentes.
// El modo 04 (borrar códigos) y el 08 (control de componentes) NO están.
const OBD_ALLOWED = [
  /^01[0-9A-F]{2}$/,
  /^02[0-9A-F]{2}00$/,
  /^03$/,
  /^07$/,
  /^09[0-9A-F]{2}$/,
  /^0A$/,
];

export class BlockedCommandError extends Error {
  constructor(cmd) {
    super(`Comando bloqueado por la política de solo lectura: "${cmd}"`);
    this.name = 'BlockedCommandError';
    this.command = cmd;
  }
}

export function normalizeCommand(cmd) {
  return String(cmd).toUpperCase().replace(/\s+/g, '');
}

export function isAllowed(cmd) {
  const c = normalizeCommand(cmd);
  if (c.startsWith('AT') || c.startsWith('ST')) return AT_ALLOWED.some(r => r.test(c));
  return OBD_ALLOWED.some(r => r.test(c));
}

export function assertAllowed(cmd) {
  if (!isAllowed(cmd)) throw new BlockedCommandError(cmd);
  return normalizeCommand(cmd);
}
