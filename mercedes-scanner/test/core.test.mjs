import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isAllowed } from '../src/safety.js';
import { parseCanResponse } from '../src/isotp.js';
import { decodeDtc, parseDtcMessage, describe } from '../src/dtc.js';
import { decodeSupported, decodePid, decodeStatus } from '../src/pids.js';
import { parseVinMessage, maskVin, describeVin } from '../src/vin.js';
import { redact, Logger } from '../src/logger.js';
import { cleanLines, detectError } from '../src/elm327.js';

test('lista blanca: permite lectura y bloquea escritura/borrado', () => {
  for (const c of ['ATZ', 'ATE0', 'ATH1', 'ATSP0', 'ATRV', 'ATDPN', 'STI', '0100', '010C', '03', '07', '0A', '0902', '020200', '020C00'])
    assert.ok(isAllowed(c), c);
  for (const c of [
    '04',          // borrar códigos
    '08',          // control de componentes
    '0101 01',     // datos extra
    '1003',        // UDS sesión extendida
    '1101',        // UDS reset ECU
    '14FFFFFF',    // UDS borrar DTC
    '2701',        // UDS seguridad
    '2EF190',      // UDS escritura DID
    '2F0101',      // UDS control E/S (actuadores)
    '3101FF00',    // UDS rutina (p. ej. regeneración forzada)
    '22F190',      // UDS lectura propietaria: bloqueada hasta tener fuente verificada
    'ATSH7E0',     // cambio de cabecera
    'ATMA',        // monitor del bus
    'ATPP0CSV01',  // parámetros programables
    'ATSP6', 'STP33', 'ATZ;04',
  ])
    assert.ok(!isAllowed(c), c);
});

test('ISO-TP: trama simple con cabecera 11 bits', () => {
  const m = parseCanResponse(['7E8 06 41 00 BE 3F A8 13 55']);
  assert.deepEqual(m, [{ ecu: '7E8', data: [0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13] }]);
});

test('ISO-TP: VIN multi-trama y dos ECU', () => {
  const lines = [
    '7E8 10 14 49 02 01 57 44 43',
    '7E9 03 41 0D 00 55 55 55 55',
    '7E8 21 31 35 36 30 30 30 30',
    '7E8 22 30 30 30 30 30 30 30',
  ];
  const m = parseCanResponse(lines);
  const vinMsg = m.find(x => x.ecu === '7E8');
  assert.equal(vinMsg.data.length, 0x14);
  assert.equal(parseVinMessage(vinMsg.data), 'WDC15600000000000');
  assert.deepEqual(m.find(x => x.ecu === '7E9').data, [0x41, 0x0D, 0x00]);
});

test('ISO-TP: descarta mensaje con trama consecutiva perdida', () => {
  const m = parseCanResponse(['7E8 10 14 49 02 01 57 44 43', '7E8 22 30 30 30 30 30 30 30']);
  assert.equal(m.length, 0);
});

test('ISO-TP: cabecera 29 bits', () => {
  const m = parseCanResponse(['18 DA F1 10 03 41 0D 32 AA AA AA AA']);
  assert.deepEqual(m, [{ ecu: '18DAF110', data: [0x41, 0x0D, 0x32] }]);
});

test('DTC: decodificación de 2 bytes (SAE J2012)', () => {
  assert.equal(decodeDtc(0x01, 0x33), 'P0133');
  assert.equal(decodeDtc(0x20, 0x02), 'P2002');
  assert.equal(decodeDtc(0x41, 0x23), 'C0123');
  assert.equal(decodeDtc(0xC1, 0x00), 'U0100');
  assert.equal(decodeDtc(0x91, 0x23), 'B1123');
  assert.equal(decodeDtc(0, 0), null);
});

test('DTC: respuesta CAN con contador y sin códigos', () => {
  assert.deepEqual(parseDtcMessage([0x43, 0x02, 0x20, 0x02, 0x04, 0x71]), ['P2002', 'P0471']);
  assert.deepEqual(parseDtcMessage([0x43, 0x00]), []);
});

test('DTC: separa significado de causas y marca códigos de fabricante', () => {
  const g = describe('P2002');
  assert.equal(g.type, 'genérico SAE');
  assert.match(g.meaning, /filtro de partículas/i);
  assert.ok(g.possibleCauses.length > 0);
  const m = describe('P1234');
  assert.equal(m.type, 'específico del fabricante');
  assert.match(m.meaning, /Mercedes/);
  assert.deepEqual(m.possibleCauses, []);
  assert.equal(describe('U1000').type, 'específico del fabricante');
  assert.equal(describe('P3400').type, 'genérico SAE');
  assert.equal(describe('P3000').type, 'específico del fabricante');
});

test('PIDs: bitmap de soporte y fórmulas', () => {
  assert.deepEqual(decodeSupported(0, [0x80, 0, 0, 0x01]), [0x01, 0x20]);
  assert.equal(decodePid(0x0C, [0x1A, 0xF8]).value, 1726);
  assert.equal(decodePid(0x05, [0x7B]).value, 83);
  assert.equal(decodePid(0x42, [0x36, 0xB0]).value, 14);
  assert.equal(decodePid(0x23, [0x0B, 0xB8]).value, 30000);
  assert.equal(decodePid(0x3C, [0x13, 0x88]).value, 460);
  assert.equal(decodePid(0x0C, [0x1A]), null); // bytes insuficientes
  assert.equal(decodePid(0x7A, [1, 2, 3]), null); // sin fórmula verificada
  assert.deepEqual(decodeStatus([0x82, 0x08, 0, 0]), { mil: true, dtcCount: 2, ignition: 'compresión (diésel)' });
});

test('VIN: enmascarado y descripción prudente', () => {
  assert.equal(maskVin('WDC15600000000000'), 'WDC**********0000');
  const d = describeVin('WDC15600000000000');
  assert.equal(d.isX156, true);
  assert.match(d.engineNote, /datacard/);
});

test('Registro: nunca guarda el VIN', () => {
  assert.equal(redact('0902', '7E8 10 14 49 02 01 57 44 43\n7E8 21 31'), '[respuesta VIN oculta: 2 línea(s)]');
  assert.equal(redact('0100', 'VIN WDC15600000000000 ok'), 'VIN [VIN OCULTO] ok');
  const log = new Logger();
  log.add('rx', '0902', '7E8 10 14 49 02 01 57 44 43');
  assert.ok(!log.toText().includes('57 44 43'));
});

test('ELM: limpieza de líneas y errores', () => {
  assert.deepEqual(cleanLines('0100\rSEARCHING...\r7E8 06 41 00 BE 3F A8 13\r\r', '0100'), ['7E8 06 41 00 BE 3F A8 13']);
  assert.equal(detectError(['NO DATA']).code, 'NO_DATA');
  assert.equal(detectError(['?']).code, 'UNKNOWN_COMMAND');
  assert.equal(detectError(['CAN ERROR']).code, 'CAN_ERROR');
  assert.equal(detectError(['7E8 03 41 0D 00']), null);
});
