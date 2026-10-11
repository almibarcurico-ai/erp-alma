// Diagnóstico OBD-II genérico (SAE J1979) de solo lectura.

import { parseCanResponse, ecuLabel } from './isotp.js';
import { decodeSupported, decodeStatus, decodePid, DPF_RAW_PIDS, LIVE_PIDS, hex } from './pids.js';
import { parseDtcMessage, decodeDtc, describe } from './dtc.js';
import { parseVinMessage, asciiFromBytes } from './vin.js';
import { AdapterError } from './elm327.js';

const CAN_PROTOCOLS = ['6', '7', '8', '9'];

export class ObdSession {
  constructor(elm) {
    this.elm = elm;
    this.supported = new Map(); // ecu -> Set(pid)
    this.protocol = null;
  }

  // Envía y devuelve mensajes por ECU. "NO DATA" = lista vacía.
  async query(cmd) {
    try {
      const lines = await this.elm.send(cmd);
      return parseCanResponse(lines);
    } catch (e) {
      if (e instanceof AdapterError && e.code === 'NO_DATA') return [];
      throw e;
    }
  }

  async connectVehicle() {
    // La primera consulta dispara la búsqueda automática de protocolo.
    const msgs = await this.query('0100');
    this.protocol = await this.elm.describeProtocol();
    if (!CAN_PROTOCOLS.includes(this.protocol.number)) {
      throw new AdapterError(`Protocolo ${this.protocol.name} no soportado por esta versión (solo CAN ISO 15765-4).`, 'PROTOCOL');
    }
    if (!msgs.length) throw new AdapterError('Ninguna ECU respondió. ¿Contacto encendido?', 'NO_ECU');
    await this.loadSupported(msgs);
    return { protocol: this.protocol, ecus: [...this.supported.keys()] };
  }

  async loadSupported(first) {
    let msgs = first;
    for (let base = 0x00; base <= 0xC0; base += 0x20) {
      if (base > 0) msgs = await this.query('01' + hex(base));
      let more = false;
      for (const m of msgs) {
        if (m.data[0] !== 0x41 || m.data[1] !== base) continue;
        const pids = decodeSupported(base, m.data.slice(2, 6));
        if (!this.supported.has(m.ecu)) this.supported.set(m.ecu, new Set());
        pids.forEach(p => this.supported.get(m.ecu).add(p));
        if (pids.includes(base + 0x20)) more = true;
      }
      if (!more) break;
    }
  }

  isSupported(pid, ecu) {
    if (ecu) return this.supported.get(ecu)?.has(pid) ?? false;
    return [...this.supported.values()].some(s => s.has(pid));
  }

  async status() {
    const out = [];
    for (const m of await this.query('0101')) {
      if (m.data[0] === 0x41 && m.data[1] === 0x01) out.push({ ecu: m.ecu, label: ecuLabel(m.ecu), ...decodeStatus(m.data.slice(2)) });
    }
    return out;
  }

  async vehicleInfo() {
    const info = { vin: null, ecus: [] };
    for (const m of await this.query('0902')) {
      const vin = parseVinMessage(m.data);
      if (vin) info.vin = vin;
    }
    const names = await this.query('090A');
    const calib = await this.query('0904');
    const ecus = new Set([...this.supported.keys(), ...names.map(m => m.ecu), ...calib.map(m => m.ecu)]);
    for (const ecu of ecus) {
      const n = names.find(m => m.ecu === ecu && m.data[0] === 0x49 && m.data[1] === 0x0A);
      const c = calib.find(m => m.ecu === ecu && m.data[0] === 0x49 && m.data[1] === 0x04);
      info.ecus.push({
        ecu,
        label: ecuLabel(ecu),
        name: n ? asciiFromBytes(n.data.slice(3)) : 'No disponible',
        calibrationId: c ? asciiFromBytes(c.data.slice(3)) : 'No disponible',
      });
    }
    return info;
  }

  async readDtcs() {
    const kinds = [['03', 0x43, 'confirmado'], ['07', 0x47, 'pendiente'], ['0A', 0x4A, 'permanente']];
    const result = [];
    for (const [cmd, ok, kind] of kinds) {
      for (const m of await this.query(cmd)) {
        if (m.data[0] !== ok) continue;
        for (const code of parseDtcMessage(m.data)) {
          result.push({ ...describe(code), kind, ecu: m.ecu, ecuLabel: ecuLabel(m.ecu) });
        }
      }
    }
    return result;
  }

  async freezeFrame() {
    const frames = new Map();
    const dtcMsgs = await this.query('020200');
    for (const m of dtcMsgs) {
      if (m.data[0] !== 0x42 || m.data[1] !== 0x02) continue;
      const code = decodeDtc(m.data[3], m.data[4]);
      frames.set(m.ecu, { ecu: m.ecu, label: ecuLabel(m.ecu), dtc: code, values: [] });
    }
    if (!frames.size) return [];

    const supported = new Map();
    for (let base = 0x00; base <= 0x40; base += 0x20) {
      const msgs = await this.query('02' + hex(base) + '00');
      let more = false;
      for (const m of msgs) {
        if (m.data[0] !== 0x42 || m.data[1] !== base) continue;
        const pids = decodeSupported(base, m.data.slice(3, 7));
        if (!supported.has(m.ecu)) supported.set(m.ecu, new Set());
        pids.forEach(p => supported.get(m.ecu).add(p));
        if (pids.includes(base + 0x20)) more = true;
      }
      if (!more) break;
    }

    const wanted = new Set();
    for (const s of supported.values()) for (const p of s) if (LIVE_PIDS[p]) wanted.add(p);
    for (const pid of [...wanted].sort((a, b) => a - b)) {
      for (const m of await this.query('02' + hex(pid) + '00')) {
        const f = frames.get(m.ecu);
        if (!f || m.data[0] !== 0x42 || m.data[1] !== pid) continue;
        const v = decodePid(pid, m.data.slice(3));
        if (v) f.values.push({ ...v, source: 'medido/calculado por la ECU (freeze frame)' });
      }
    }
    return [...frames.values()];
  }

  async readLive(pids) {
    const out = [];
    for (const pid of pids) {
      if (!this.isSupported(pid)) {
        out.push({ pid, name: LIVE_PIDS[pid]?.name ?? `PID ${hex(pid)}`, unit: LIVE_PIDS[pid]?.unit ?? '', value: null, available: false });
        continue;
      }
      for (const m of await this.query('01' + hex(pid))) {
        if (m.data[0] !== 0x41 || m.data[1] !== pid) continue;
        const v = decodePid(pid, m.data.slice(2));
        if (v) out.push({ ...v, ecu: m.ecu, available: true });
      }
    }
    return out;
  }

  // PIDs genéricos de DPF/escape: solo informa si la ECU los declara y entrega
  // los bytes crudos. Sin conversión (estructura no verificada en la app).
  async dpfGeneric() {
    const out = [];
    for (const [pidStr, name] of Object.entries(DPF_RAW_PIDS)) {
      const pid = Number(pidStr);
      const entry = { pid, name, supported: this.isSupported(pid), raw: null };
      if (entry.supported) {
        const m = (await this.query('01' + hex(pid))).find(x => x.data[0] === 0x41 && x.data[1] === pid);
        entry.raw = m ? m.data.slice(2).map(b => hex(b)).join(' ') : null;
      }
      out.push(entry);
    }
    return out;
  }
}
