// Transporte SIMULADO: imita un ELM327 con cabeceras activas sobre CAN
// 11 bits/500 kbps. Todos los datos son ficticios y sirven solo para probar
// la app sin el vehículo. Nunca se mezclan con una conexión real.

const h = n => n.toString(16).toUpperCase().padStart(2, '0');

export const SIM_VIN = 'WDC15600000000000'; // ficticio

function encodeSupported(base, pids) {
  const b = [0, 0, 0, 0];
  for (const p of pids) {
    const i = p - base - 1;
    if (i >= 0 && i < 32) b[i >> 3] |= 0x80 >> (i & 7);
  }
  return b;
}

function dtcBytes(code) {
  const letter = 'PCBU'.indexOf(code[0]);
  const v = parseInt(code.slice(1), 16); // 4 dígitos hex: d1 (2 bits) + 3 nibbles
  return [(letter << 6) | (v >> 8), v & 0xff];
}

const ascii = s => [...s].map(c => c.charCodeAt(0));

// Escenario por defecto: Check Engine encendido con códigos relacionados al DPF.
export const DEFAULT_SCENARIO = {
  ecus: {
    '7E8': {
      pids: [0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x1F, 0x20, 0x21, 0x23, 0x2F, 0x31, 0x33, 0x40, 0x42, 0x46, 0x49, 0x4D, 0x4E, 0x5C, 0x60, 0x7A, 0x80],
      confirmed: ['P2002', 'P0471'],
      pending: ['P0401'],
      permanent: ['P2002'],
      name: 'ECM-EngineControl',
      calibration: 'SIMCAL0001',
      freeze: { dtc: 'P2002', values: { 0x04: [0x8C], 0x05: [0x7D], 0x0C: [0x07, 0xD0], 0x0D: [0x50], 0x0B: [0x91] } },
    },
    '7E9': {
      pids: [0x01, 0x05, 0x0D],
      confirmed: [], pending: [], permanent: [],
      name: 'TCM-TransmissionCtl',
      calibration: 'SIMCAL0002',
      freeze: null,
    },
  },
};

export class SimulatorTransport {
  constructor({ scenario = DEFAULT_SCENARIO, latencyMs = 20, rand = Math.random } = {}) {
    this.kind = 'simulación';
    this.scenario = scenario;
    this.latencyMs = latencyMs;
    this.rand = rand;
    this.dataCb = () => {};
    this.lostCb = () => {};
    this.open_ = false;
    this.searched = false;
    this.headers = false;
    this.received = []; // comandos recibidos, para pruebas
  }

  onData(cb) { this.dataCb = cb; }
  onDisconnect(cb) { this.lostCb = cb; }
  async open() { this.open_ = true; }
  async close() { this.open_ = false; }
  portInfo() { return { simulated: true }; }

  // Simula desconectar el cable USB.
  unplug() { this.open_ = false; this.lostCb(); }

  async write(text) {
    if (!this.open_) throw new Error('puerto cerrado');
    const cmd = text.replace(/\r/g, '').toUpperCase().replace(/\s+/g, '');
    this.received.push(cmd);
    const lines = this.respond(cmd);
    setTimeout(() => this.open_ && this.dataCb(lines.join('\r') + '\r\r>'), this.latencyMs);
  }

  respond(cmd) {
    if (cmd === 'ATZ' || cmd === 'ATWS') { this.headers = false; this.searched = false; return ['', 'ELM327 v1.5 (SIMULADO)']; }
    if (cmd === 'ATI') return ['ELM327 v1.5 (SIMULADO)'];
    if (cmd === 'AT@1') return ['SIMULADOR OBD-II'];
    if (cmd === 'STI') return ['?'];
    if (cmd === 'ATRV') return ['12.6V'];
    if (cmd === 'ATDP') return ['AUTO, ISO 15765-4 (CAN 11/500)'];
    if (cmd === 'ATDPN') return ['A6'];
    if (cmd === 'ATH1') { this.headers = true; return ['OK']; }
    if (cmd.startsWith('AT')) return ['OK'];

    const pre = this.searched ? [] : ['SEARCHING...'];
    this.searched = true;
    const msgs = [];
    for (const [ecu, e] of Object.entries(this.scenario.ecus)) {
      const data = this.ecuAnswer(e, cmd);
      if (data) msgs.push(...this.frames(ecu, data));
    }
    return msgs.length ? [...pre, ...msgs] : [...pre, 'NO DATA'];
  }

  ecuAnswer(e, cmd) {
    const mode = cmd.slice(0, 2);
    const pid = parseInt(cmd.slice(2, 4), 16);
    if (mode === '01') {
      if (pid % 0x20 === 0) {
        const pids = e.pids.filter(p => p > pid && p <= pid + 0x20);
        if (pid !== 0 && !e.pids.includes(pid)) return null;
        return [0x41, pid, ...encodeSupported(pid, pids)];
      }
      if (!e.pids.includes(pid)) return null;
      return [0x41, pid, ...this.liveValue(e, pid)];
    }
    if (mode === '02') {
      if (!e.freeze) return null;
      if (pid === 0x02) return [0x42, 0x02, 0x00, ...dtcBytes(e.freeze.dtc)];
      if (pid % 0x20 === 0) {
        const pids = [0x02, ...Object.keys(e.freeze.values).map(Number)].filter(p => p > pid && p <= pid + 0x20);
        return pid === 0 ? [0x42, 0x00, 0x00, ...encodeSupported(0, pids)] : null;
      }
      const v = e.freeze.values[pid];
      return v ? [0x42, pid, 0x00, ...v] : null;
    }
    if (cmd === '03') return [0x43, e.confirmed.length, ...e.confirmed.flatMap(dtcBytes)];
    if (cmd === '07') return [0x47, e.pending.length, ...e.pending.flatMap(dtcBytes)];
    if (cmd === '0A') return [0x4A, e.permanent.length, ...e.permanent.flatMap(dtcBytes)];
    if (mode === '09') {
      if (pid === 0x02 && e === this.scenario.ecus['7E8']) return [0x49, 0x02, 0x01, ...ascii(SIM_VIN)];
      if (pid === 0x0A) return [0x49, 0x0A, 0x01, ...ascii(e.name.padEnd(20, '\0'))];
      if (pid === 0x04) return [0x49, 0x04, 0x01, ...ascii(e.calibration.padEnd(16, '\0'))];
      return null;
    }
    return null;
  }

  liveValue(e, pid) {
    const r = (a, b) => Math.round(a + this.rand() * (b - a));
    const mil = e.confirmed.length ? 0x80 : 0;
    switch (pid) {
      case 0x01: return [mil | e.confirmed.length, 0x08, 0x00, 0x00];
      case 0x04: return [r(40, 70)];
      case 0x05: return [r(118, 124)]; // ~80 °C
      case 0x0B: return [r(100, 140)];
      case 0x0C: { const rpm = r(780, 820) * 4; return [rpm >> 8, rpm & 0xff]; }
      case 0x0D: return [0];
      case 0x0F: return [r(60, 70)];
      case 0x10: { const v = r(900, 1200); return [v >> 8, v & 0xff]; }
      case 0x1F: return [0x01, 0x2C];
      case 0x21: return [0x00, 0x7B];
      case 0x23: { const v = r(2800, 3200); return [v >> 8, v & 0xff]; }
      case 0x2F: return [0x80];
      case 0x31: return [0x04, 0xD2];
      case 0x33: return [0x62];
      case 0x42: { const v = r(13900, 14200); return [v >> 8, v & 0xff]; }
      case 0x46: return [0x3C];
      case 0x49: return [0x00];
      case 0x4D: return [0x00, 0x5A];
      case 0x4E: return [0x01, 0x40];
      case 0x5C: return [r(120, 126)];
      case 0x7A: return [0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]; // bytes ficticios
      default: return [0];
    }
  }

  // Formatea como lo muestra un ELM327 con ATH1 (ISO-TP, tramas de 8 bytes).
  frames(ecu, data) {
    const pad = a => [...a, ...Array(8 - a.length).fill(0x55)].slice(0, 8);
    const line = b => (this.headers ? ecu + ' ' : '') + pad(b).map(h).join(' ');
    if (data.length <= 7) return [line([data.length, ...data])];
    const out = [line([0x10 | (data.length >> 8), data.length & 0xff, ...data.slice(0, 6)])];
    let seq = 1;
    for (let i = 6; i < data.length; i += 7) {
      out.push(line([0x20 | (seq & 0x0f), ...data.slice(i, i + 7)]));
      seq++;
    }
    return out;
  }
}
