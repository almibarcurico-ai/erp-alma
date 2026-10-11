// Pruebas de extremo a extremo contra el simulador (sin vehículo).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Elm327, DisconnectedError } from '../src/elm327.js';
import { ObdSession } from '../src/obd.js';
import { SimulatorTransport, SIM_VIN } from '../src/transports/simulator.js';
import { Logger } from '../src/logger.js';
import { BlockedCommandError } from '../src/safety.js';
import { mercedesCapabilities } from '../src/mercedes.js';
import { buildReport, reportToText } from '../src/report.js';
import { DEFAULT_LIVE } from '../src/pids.js';

async function setup(opts = {}) {
  const sim = new SimulatorTransport({ latencyMs: 1, rand: () => 0.5 });
  const logger = new Logger();
  const elm = new Elm327(sim, { logger, minIntervalMs: 0, timeoutMs: 500, ...opts });
  await elm.open();
  const adapter = await elm.initialize();
  const obd = new ObdSession(elm);
  return { sim, logger, elm, obd, adapter };
}

test('flujo completo de diagnóstico en simulación', async () => {
  const { sim, logger, elm, obd, adapter } = await setup();
  assert.match(adapter.elmId, /SIMULADO/);
  assert.equal(adapter.stnId, null);

  const conn = await obd.connectVehicle();
  assert.equal(conn.protocol.number, '6');
  assert.deepEqual(conn.ecus.sort(), ['7E8', '7E9']);
  assert.ok(obd.isSupported(0x7A, '7E8'));
  assert.ok(obd.isSupported(0x5C, '7E8'));

  const status = await obd.status();
  const ecm = status.find(s => s.ecu === '7E8');
  assert.equal(ecm.mil, true);
  assert.equal(ecm.dtcCount, 2);

  const info = await obd.vehicleInfo();
  assert.equal(info.vin, SIM_VIN);
  assert.equal(info.ecus.find(e => e.ecu === '7E9').name, 'TCM-TransmissionCtl');

  const dtcs = await obd.readDtcs();
  assert.deepEqual(dtcs.map(d => `${d.code}:${d.kind}`).sort(), ['P0401:pendiente', 'P0471:confirmado', 'P2002:confirmado', 'P2002:permanente']);

  const ff = await obd.freezeFrame();
  assert.equal(ff.length, 1);
  assert.equal(ff[0].dtc, 'P2002');
  assert.equal(ff[0].values.find(v => v.pid === 0x0C).value, 500);
  assert.equal(ff[0].values.find(v => v.pid === 0x05).value, 85);

  const live = await obd.readLive(DEFAULT_LIVE);
  const rpm = live.find(v => v.pid === 0x0C && v.ecu === '7E8');
  assert.ok(rpm.value >= 780 && rpm.value <= 820);
  assert.equal(live.filter(v => v.pid === 0x0D).length, 2); // responde motor y TCU

  const dpf = await obd.dpfGeneric();
  assert.equal(dpf.find(p => p.pid === 0x7A).supported, true);
  assert.equal(dpf.find(p => p.pid === 0x7A).raw, '07 00 00 00 00 00 00');
  assert.equal(dpf.find(p => p.pid === 0x7C).supported, false);

  const merc = mercedesCapabilities({ dpfGeneric: dpf, ecus: conn.ecus });
  assert.ok(merc.dpf.every(p => p.status === 'No disponible' && p.value === null));
  assert.ok(merc.transmission.every(p => p.status === 'No disponible'));

  // Solo se enviaron comandos permitidos; nunca el modo 04.
  assert.ok(!sim.received.includes('04'));
  assert.ok(sim.received.every(c => !/^(04|08|1[0-9A-F]|2[0-9A-F]|3[0-9A-F])/.test(c) || c.startsWith('AT')));

  // El registro no contiene el VIN.
  assert.ok(!logger.toText().includes(SIM_VIN));

  const report = buildReport({ mode: sim.kind, adapter, protocol: conn.protocol, vehicle: { vin: info.vin }, status, dtcs, freezeFrames: ff, live, dpfGeneric: dpf, mercedes: merc });
  assert.match(report.warning, /SIMULADOS/);
  const txt = reportToText(report);
  assert.match(txt, /VIN: WDC15600000000000/);
  assert.match(txt, /Modo: SIMULACIÓN/);
  assert.match(txt, /Carga de hollín calculada: No disponible/);
  await elm.close();
});

test('comando bloqueado no llega al adaptador', async () => {
  const { sim, elm, logger } = await setup();
  const before = sim.received.length;
  await assert.rejects(elm.send('04'), BlockedCommandError);
  await assert.rejects(elm.send('3101FF00'), BlockedCommandError);
  assert.equal(sim.received.length, before);
  assert.ok(logger.entries.some(e => e.kind === 'blocked'));
  await elm.close();
});

test('desconexión: rechaza consultas pendientes y posteriores', async () => {
  const { sim, elm } = await setup();
  let notified = false;
  elm.onDisconnect = () => { notified = true; };
  sim.latencyMs = 50;
  const p = elm.send('0100');
  setTimeout(() => sim.unplug(), 5);
  await assert.rejects(p, DisconnectedError);
  assert.ok(notified);
  await assert.rejects(elm.send('0100'), DisconnectedError);
});

test('timeout cuando el adaptador no responde', async () => {
  const { sim, elm } = await setup({ timeoutMs: 30 });
  sim.dataCb = () => {}; // el adaptador "se cuelga"
  elm.transport.dataCb = () => {};
  await assert.rejects(elm.send('0100'), e => e.code === 'TIMEOUT');
  await elm.close();
});

test('limitación de frecuencia entre comandos', async () => {
  const sim = new SimulatorTransport({ latencyMs: 0 });
  const elm = new Elm327(sim, { minIntervalMs: 40, timeoutMs: 500 });
  await elm.open();
  const t0 = Date.now();
  await Promise.all([elm.send('ATE0'), elm.send('ATL0'), elm.send('ATS1')]);
  assert.ok(Date.now() - t0 >= 75, `demasiado rápido: ${Date.now() - t0} ms`);
  await elm.close();
});
