// Driver ELM327 / STN (OBDLink) sobre un transporte de texto (Web Serial o
// simulador). Serializa las consultas, impone un intervalo mínimo entre
// comandos, aplica timeout y valida cada comando contra la lista blanca.

import { assertAllowed, BlockedCommandError } from './safety.js';

export class AdapterError extends Error {
  constructor(message, code, raw) {
    super(message);
    this.name = 'AdapterError';
    this.code = code;
    this.raw = raw;
  }
}

export class DisconnectedError extends Error {
  constructor(message = 'Adaptador desconectado') {
    super(message);
    this.name = 'DisconnectedError';
  }
}

// Respuestas de error documentadas en la hoja de datos del ELM327.
const ELM_ERRORS = [
  ['NO DATA', 'NO_DATA'],
  ['UNABLE TO CONNECT', 'UNABLE_TO_CONNECT'],
  ['CAN ERROR', 'CAN_ERROR'],
  ['BUS INIT: ...ERROR', 'BUS_INIT_ERROR'],
  ['BUS ERROR', 'BUS_ERROR'],
  ['BUS BUSY', 'BUS_BUSY'],
  ['BUFFER FULL', 'BUFFER_FULL'],
  ['DATA ERROR', 'DATA_ERROR'],
  ['FB ERROR', 'FB_ERROR'],
  ['LV RESET', 'LV_RESET'],
  ['STOPPED', 'STOPPED'],
  ['ERR', 'ERR'],
  ['?', 'UNKNOWN_COMMAND'],
];

const sleep = ms => new Promise(r => setTimeout(r, ms));

export class Elm327 {
  constructor(transport, { logger, minIntervalMs = 120, timeoutMs = 5000, clock = () => Date.now() } = {}) {
    this.transport = transport;
    this.logger = logger;
    this.minIntervalMs = minIntervalMs;
    this.timeoutMs = timeoutMs;
    this.clock = clock;
    this.buffer = '';
    this.pending = null;
    this.queue = Promise.resolve();
    this.lastSentAt = 0;
    this.connected = false;
    this.info = {};
    this.onDisconnect = null;
  }

  async open() {
    this.transport.onData(chunk => this._onData(chunk));
    this.transport.onDisconnect(() => this._onTransportLost());
    await this.transport.open();
    this.connected = true;
    this.logger?.add('info', null, `Transporte abierto (${this.transport.kind})`);
  }

  async close() {
    this.connected = false;
    try { await this.transport.close(); } catch { /* ya cerrado */ }
    this._failPending(new DisconnectedError('Conexión cerrada'));
    this.logger?.add('info', null, 'Transporte cerrado');
  }

  _onTransportLost() {
    if (!this.connected) return;
    this.connected = false;
    this.logger?.add('error', null, 'Se perdió la conexión con el adaptador');
    this._failPending(new DisconnectedError());
    this.onDisconnect?.();
  }

  _failPending(err) {
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.reject(err);
      this.pending = null;
    }
    this.buffer = '';
  }

  _onData(chunk) {
    this.buffer += chunk;
    const idx = this.buffer.indexOf('>');
    if (idx === -1 || !this.pending) {
      if (!this.pending) this.buffer = this.buffer.length > 4096 ? '' : this.buffer;
      return;
    }
    const raw = this.buffer.slice(0, idx);
    this.buffer = this.buffer.slice(idx + 1);
    const p = this.pending;
    this.pending = null;
    clearTimeout(p.timer);
    p.resolve(raw);
  }

  // Envía un comando (validado) y devuelve las líneas de respuesta limpias.
  send(cmd, { timeoutMs } = {}) {
    let normalized;
    try {
      normalized = assertAllowed(cmd);
    } catch (e) {
      if (e instanceof BlockedCommandError) this.logger?.add('blocked', String(cmd), e.message);
      return Promise.reject(e);
    }
    const run = () => this._sendNow(normalized, timeoutMs ?? this.timeoutMs);
    const result = this.queue.then(run, run);
    this.queue = result.catch(() => {});
    return result;
  }

  async _sendNow(cmd, timeoutMs) {
    if (!this.connected) throw new DisconnectedError();
    const wait = this.lastSentAt + this.minIntervalMs - this.clock();
    if (wait > 0) await sleep(wait);

    const raw = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending = null;
        reject(new AdapterError(`Sin respuesta en ${timeoutMs} ms`, 'TIMEOUT'));
      }, timeoutMs);
      this.pending = { resolve, reject, timer };
      this.buffer = '';
      this.lastSentAt = this.clock();
      this.logger?.add('tx', cmd);
      this.transport.write(cmd + '\r').catch(err => {
        clearTimeout(timer);
        this.pending = null;
        reject(new DisconnectedError(`Error al escribir: ${err.message}`));
      });
    });

    const lines = cleanLines(raw, cmd);
    this.logger?.add('rx', cmd, lines.join('\n'));
    const err = detectError(lines);
    if (err) throw new AdapterError(err.message, err.code, lines);
    return lines;
  }

  // Inicialización mínima. Solo configura el adaptador.
  async initialize() {
    await this.send('ATZ', { timeoutMs: 8000 }).catch(() => {}); // algunos clones no responden limpio al reset
    await this.send('ATE0');
    await this.send('ATL0');
    await this.send('ATS1');
    await this.send('ATH1');
    await this.send('ATAT1');
    await this.send('ATSP0');

    const info = {};
    info.elmId = (await this.send('ATI').catch(() => ['?'])).join(' ');
    info.device = (await this.send('AT@1').catch(() => ['No disponible'])).join(' ');
    info.stnId = await this.send('STI').then(l => l.join(' ')).catch(() => null);
    info.voltage = (await this.send('ATRV').catch(() => ['No disponible'])).join(' ');
    this.info = info;
    return info;
  }

  async describeProtocol() {
    const name = (await this.send('ATDP')).join(' ');
    const num = (await this.send('ATDPN')).join(' ').replace(/^A/, '');
    return { name, number: num };
  }
}

export function cleanLines(raw, cmd) {
  return String(raw)
    .split(/[\r\n]+/)
    .map(l => l.trim())
    .filter(l => l && l !== cmd && !/^SEARCHING/i.test(l) && !/^BUS INIT/i.test(l) || /ERROR/.test(l))
    .filter(l => l !== '>');
}

export function detectError(lines) {
  const joined = lines.join(' ').toUpperCase();
  if (!lines.length) return { code: 'EMPTY', message: 'Respuesta vacía' };
  for (const [text, code] of ELM_ERRORS) {
    if (text === '?' ? lines.some(l => l.trim() === '?') : joined.includes(text)) {
      return { code, message: `Adaptador respondió: ${text}` };
    }
  }
  return null;
}
