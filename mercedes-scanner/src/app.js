import { Elm327, DisconnectedError } from './elm327.js';
import { ObdSession } from './obd.js';
import { Logger } from './logger.js';
import { WebSerialTransport } from './transports/webserial.js';
import { SimulatorTransport } from './transports/simulator.js';
import { DEFAULT_LIVE, hex } from './pids.js';
import { describeVin, maskVin } from './vin.js';
import { mercedesCapabilities } from './mercedes.js';
import { buildReport, reportToText, download } from './report.js';

const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = v => (v === null || v === undefined ? '<span class="na">No disponible</span>' : Number.isInteger(v) ? v : v.toFixed(2));

const logger = new Logger();
let elm = null, obd = null, transport = null, live = false;
const state = {};

logger.onEntry(e => {
  const el = $('log');
  el.textContent += `${e.t.slice(11, 23)} ${e.kind.padEnd(7)} ${e.command ?? ''} ${e.response ? '→ ' + e.response.replace(/\n/g, ' | ') : ''}\n`;
  el.scrollTop = el.scrollHeight;
});

function setError(msg) { $('error').textContent = msg ?? ''; }

function setBanner(kind) {
  const b = $('banner');
  b.className = 'banner ' + kind;
  b.textContent = kind === 'sim' ? 'MODO SIMULACIÓN — los datos son ficticios, no provienen del vehículo'
    : kind === 'real' ? 'CONEXIÓN REAL con el adaptador USB — solo lectura'
    : 'Sin conexión';
}

function setConnected(on) {
  $('connect').disabled = on;
  $('mode').disabled = on;
  $('baud').disabled = on;
  $('disconnect').disabled = !on;
  $('scan').disabled = !on;
  $('liveStart').disabled = !on || !obd?.protocol;
  if (!on) { live = false; $('liveStop').disabled = true; }
}

$('mode').addEventListener('change', () => {
  const real = $('mode').value === 'real';
  $('baudWrap').hidden = !real;
  $('serialHint').hidden = !real;
});

$('connect').addEventListener('click', async () => {
  setError();
  const real = $('mode').value === 'real';
  if (real && !WebSerialTransport.isSupported()) {
    setError('Este navegador no soporta Web Serial. Use Chrome o Edge y abra la app desde http://localhost.');
    return;
  }
  transport = real ? new WebSerialTransport({ baudRate: Number($('baud').value) }) : new SimulatorTransport();
  elm = new Elm327(transport, { logger, minIntervalMs: 120, timeoutMs: 5000 });
  elm.onDisconnect = () => {
    setConnected(false);
    setBanner('off');
    setError('Se perdió la conexión con el adaptador. Revise el cable y vuelva a conectar.');
  };
  try {
    await elm.open();
    setBanner(real ? 'real' : 'sim');
    const info = await elm.initialize();
    state.adapter = { ...info, port: transport.portInfo(), mode: transport.kind };
    renderAdapter();
    obd = new ObdSession(elm);
    setConnected(true);
  } catch (e) {
    setError(`No se pudo conectar: ${e.message}`);
    await elm.close();
    setBanner('off');
    setConnected(false);
  }
});

$('disconnect').addEventListener('click', async () => {
  live = false;
  await elm?.close();
  setConnected(false);
  setBanner('off');
});

function renderAdapter() {
  const a = state.adapter;
  const stn = a.stnId ? `Sí (${esc(a.stnId)})` : 'No (no respondió a STI)';
  const p = a.port.simulated ? 'Simulado' : `USB VID ${a.port.usbVendorId} / PID ${a.port.usbProductId}, ${a.port.baudRate} baud`;
  $('adapter').innerHTML = `
    <dt>Identificación</dt><dd class="mono">${esc(a.elmId)}</dd>
    <dt>Dispositivo</dt><dd class="mono">${esc(a.device)}</dd>
    <dt>Chip STN (OBDLink)</dt><dd>${stn}</dd>
    <dt>Voltaje (pin 16)</dt><dd class="mono">${esc(a.voltage)}</dd>
    <dt>Puerto</dt><dd class="mono">${esc(p)}</dd>
    <dt>Compatibilidad</dt><dd>${compatNote(a)}</dd>`;
}

function compatNote(a) {
  if (a.mode === 'simulación') return 'Simulación.';
  const notes = [];
  if (a.stnId) notes.push('Adaptador con chip STN: buen soporte de CAN/ISO-TP.');
  else if (/v(1\.5|2\.1)/i.test(a.elmId)) notes.push('Reporta "ELM327 v1.5/v2.1": es típico de clones; la versión declarada puede no ser real. Sirve para OBD-II genérico, pero puede fallar en respuestas largas.');
  else notes.push('ELM327 o compatible: válido para OBD-II genérico.');
  notes.push('Ningún ELM327/STN da por sí solo diagnóstico Mercedes completo (módulos, DPF detallado, TCU, paletas).');
  return notes.map(esc).join('<br>');
}

$('scan').addEventListener('click', async () => {
  setError();
  live = false;
  $('scan').disabled = true;
  try {
    if (!obd.protocol) {
      const c = await obd.connectVehicle();
      state.protocol = c.protocol;
      state.ecus = c.ecus;
      $('liveStart').disabled = false;
    }
    state.status = await obd.status();
    const info = await obd.vehicleInfo();
    state.vehicle = { vin: info.vin, vinInfo: describeVin(info.vin), ecus: info.ecus };
    renderVehicle();
    state.dtcs = await obd.readDtcs();
    renderDtcs();
    state.freezeFrames = await obd.freezeFrame();
    renderFreeze();
    state.live = await obd.readLive(DEFAULT_LIVE);
    renderLive();
    state.dpfGeneric = await obd.dpfGeneric();
    state.mercedes = mercedesCapabilities({ dpfGeneric: state.dpfGeneric, ecus: state.ecus });
    renderDpf();
    renderTrans();
    $('expJson').disabled = $('expTxt').disabled = false;
  } catch (e) {
    setError(e instanceof DisconnectedError ? e.message : `Error de lectura: ${e.message}`);
  } finally {
    $('scan').disabled = !elm?.connected;
  }
});

$('showVin').addEventListener('change', () => state.vehicle && renderVehicle());

function renderVehicle() {
  const v = state.vehicle, vi = v.vinInfo;
  const vin = v.vin ? ($('showVin').checked ? v.vin : maskVin(v.vin)) : null;
  const ecus = v.ecus.map(e => `${esc(e.label)}: ${esc(e.name)} <span class="muted mono">cal. ${esc(e.calibrationId)}</span>`).join('<br>');
  const st = (state.status ?? []).map(s =>
    `${esc(s.label)}: <span class="tag ${s.mil ? 'bad' : 'ok'}">MIL ${s.mil ? 'encendida' : 'apagada'}</span> ${s.dtcCount} código(s); encendido por ${esc(s.ignition)}`).join('<br>');
  $('vehicle').innerHTML = `
    <dt>VIN</dt><dd class="mono">${vin ? esc(vin) : '<span class="na">No disponible</span>'}</dd>
    ${vi ? `<dt>Fabricante (WMI)</dt><dd>${esc(vi.maker)}</dd>
    <dt>Baumuster (indicativo)</dt><dd class="mono">${esc(vi.baumuster ?? '-')} ${vi.isX156 ? '<span class="tag ok">serie 156</span>' : vi.isX156 === false ? '<span class="tag warn">no parece serie 156</span>' : ''}</dd>
    <dt>Motor / versión</dt><dd>${esc(vi.engineNote)}</dd>` : ''}
    <dt>Protocolo</dt><dd>${esc(state.protocol?.name)}</dd>
    <dt>ECUs que responden</dt><dd>${ecus || '-'}</dd>
    <dt>Estado</dt><dd>${st || '-'}</dd>`;
}

function renderDtcs() {
  const rows = state.dtcs.map(d => `<tr>
    <td class="mono"><b>${esc(d.code)}</b></td>
    <td><span class="tag ${d.kind === 'confirmado' ? 'bad' : d.kind === 'pendiente' ? 'warn' : ''}">${esc(d.kind)}</span></td>
    <td>${esc(d.ecuLabel)}</td>
    <td>${esc(d.type)}</td>
    <td><b>Significado:</b> ${esc(d.meaning)}${d.possibleCauses.length ? `<br><b>Posibles causas (orientativo):</b> ${d.possibleCauses.map(esc).join('; ')}` : ''}</td></tr>`).join('');
  $('dtcs').innerHTML = `<tr><th>Código</th><th>Tipo</th><th>ECU</th><th>Origen</th><th>Descripción</th></tr>` +
    (rows || `<tr><td colspan="5" class="muted">Sin códigos reportados por OBD-II genérico. Puede haber códigos en módulos que solo se leen con diagnóstico Mercedes.</td></tr>`);
}

function renderFreeze() {
  if (!state.freezeFrames.length) { $('freeze').innerHTML = '<span class="na">No disponible (ninguna ECU entregó freeze frame).</span>'; return; }
  $('freeze').className = '';
  $('freeze').innerHTML = state.freezeFrames.map(f => `
    <p><b>${esc(f.label)}</b>: código que lo generó <span class="mono">${esc(f.dtc ?? 'No disponible')}</span></p>
    <table><tr><th>Parámetro</th><th>Valor</th><th>Unidad</th></tr>
    ${f.values.map(v => `<tr><td>${esc(v.name)}</td><td class="mono">${fmt(v.value)}</td><td>${esc(v.unit)}</td></tr>`).join('')}</table>`).join('');
}

function renderLive() {
  $('live').innerHTML = `<tr><th>PID</th><th>Parámetro</th><th>Valor</th><th>Unidad</th><th>ECU</th></tr>` +
    state.live.map(v => `<tr><td class="mono">${hex(v.pid)}</td><td>${esc(v.name)}</td><td class="mono">${v.available ? fmt(v.value) : '<span class="na">No disponible</span>'}</td><td>${esc(v.unit)}</td><td class="muted">${esc(v.ecu ?? '')}</td></tr>`).join('');
}

function renderDpf() {
  const m = state.mercedes;
  $('dpf').className = '';
  $('dpf').innerHTML = `
    <div class="notice">Los valores se distinguen entre <b>medidos</b> por un sensor y <b>estimados</b> por la ECU. Nada aquí basta para declarar el DPF obstruido.</div>
    <table style="margin-top:8px"><tr><th>Parámetro</th><th>Tipo</th><th>Valor</th></tr>
    ${m.dpf.map(p => `<tr><td>${esc(p.name)}</td><td class="muted">${esc(p.kind)}</td><td><span class="na">${esc(p.status)}</span></td></tr>`).join('')}</table>
    <p class="muted">${esc(m.dpf[0].reason)}</p>
    <p><b>PIDs SAE genéricos de DPF/escape</b> (bytes crudos, sin convertir a unidades porque la app no tiene su estructura verificada):</p>
    <table><tr><th>PID</th><th>Descripción</th><th>Bytes</th></tr>
    ${state.dpfGeneric.map(p => `<tr><td class="mono">${hex(p.pid)}</td><td>${esc(p.name)}</td><td class="mono">${p.supported ? esc(p.raw ?? 'sin respuesta') : '<span class="na">No disponible (la ECU no lo declara)</span>'}</td></tr>`).join('')}</table>`;
}

function renderTrans() {
  const m = state.mercedes;
  $('trans').className = '';
  $('trans').innerHTML = `
    <table><tr><th>Parámetro</th><th>Estado</th></tr>
    ${m.transmission.map(p => `<tr><td>${esc(p.name)}</td><td><span class="na">${esc(p.status)}</span><br><span class="muted">${esc(p.reason)}</span></td></tr>`).join('')}</table>
    <p><b>Qué hace falta para leerlos:</b></p><ul>${m.hardwareNeeded.map(h => `<li>${esc(h)}</li>`).join('')}</ul>`;
}

$('liveStart').addEventListener('click', async () => {
  live = true;
  $('liveStart').disabled = true;
  $('liveStop').disabled = false;
  $('scan').disabled = true;
  while (live && elm?.connected) {
    const t0 = Date.now();
    try {
      state.live = await obd.readLive(DEFAULT_LIVE);
      renderLive();
    } catch (e) {
      setError(`Lectura en vivo detenida: ${e.message}`);
      break;
    }
    await new Promise(r => setTimeout(r, Math.max(0, 1000 - (Date.now() - t0))));
  }
  live = false;
  $('liveStop').disabled = true;
  $('liveStart').disabled = !elm?.connected;
  $('scan').disabled = !elm?.connected;
});

$('liveStop').addEventListener('click', () => { live = false; });

function report() {
  return buildReport({ mode: transport.kind, ...state, protocol: state.protocol });
}
const stamp = () => new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
$('expJson').addEventListener('click', () => download(`diagnostico-${stamp()}.json`, JSON.stringify(report(), null, 2)));
$('expTxt').addEventListener('click', () => download(`diagnostico-${stamp()}.txt`, reportToText(report()), 'text/plain'));
$('expLog').addEventListener('click', () => download(`registro-${stamp()}.txt`, logger.toText(), 'text/plain'));
