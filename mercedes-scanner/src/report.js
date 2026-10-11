// Exportación del diagnóstico. El informe incluye el VIN completo porque es
// un archivo del propietario. El registro de depuración va aparte y sin VIN.

export const APP_VERSION = '0.1.0';

export function buildReport({ mode, adapter, protocol, vehicle, status, dtcs, freezeFrames, live, dpfGeneric, mercedes, now = new Date() }) {
  return {
    app: 'mercedes-scanner',
    version: APP_VERSION,
    generatedAt: now.toISOString(),
    mode, // 'simulación' | 'real'
    warning: mode === 'simulación'
      ? 'DATOS SIMULADOS: este informe no proviene de un vehículo real.'
      : 'Informe de solo lectura. No reemplaza una inspección profesional ni indica si el vehículo es seguro para conducir.',
    adapter,
    protocol,
    vehicle,
    status,
    dtcs,
    freezeFrames,
    live,
    dpfGeneric,
    mercedes,
  };
}

const fmt = v => (v === null || v === undefined ? 'No disponible' : typeof v === 'number' ? (Number.isInteger(v) ? String(v) : v.toFixed(2)) : String(v));

export function reportToText(r) {
  const L = [];
  L.push(`DIAGNÓSTICO OBD-II — ${r.generatedAt}`);
  L.push(`Modo: ${r.mode.toUpperCase()}`);
  L.push(r.warning, '');
  L.push(`VIN: ${r.vehicle?.vin ?? 'No disponible'}`);
  if (r.vehicle?.vinInfo) L.push(`Fabricante (WMI): ${r.vehicle.vinInfo.maker}  Baumuster (indicativo): ${r.vehicle.vinInfo.baumuster ?? '-'}`);
  L.push(`Adaptador: ${r.adapter?.elmId ?? '-'} ${r.adapter?.stnId ? '/ ' + r.adapter.stnId : ''}  Voltaje medido por el adaptador: ${r.adapter?.voltage ?? '-'}`);
  L.push(`Protocolo: ${r.protocol?.name ?? '-'}`, '');
  for (const s of r.status ?? []) L.push(`${s.label}: MIL ${s.mil ? 'ENCENDIDA' : 'apagada'}, ${s.dtcCount} código(s) declarados, encendido por ${s.ignition}`);
  L.push('', 'CÓDIGOS DE FALLA');
  if (!r.dtcs?.length) L.push('  Sin códigos reportados por OBD-II genérico.');
  for (const d of r.dtcs ?? []) {
    L.push(`  ${d.code} [${d.kind}] ${d.ecuLabel} — ${d.type}`);
    L.push(`    Significado: ${d.meaning}`);
    if (d.possibleCauses.length) L.push(`    Posibles causas (orientativo): ${d.possibleCauses.join('; ')}`);
  }
  L.push('', 'FREEZE FRAME');
  if (!r.freezeFrames?.length) L.push('  No disponible.');
  for (const f of r.freezeFrames ?? []) {
    L.push(`  ${f.label} — código que lo generó: ${f.dtc ?? 'No disponible'}`);
    for (const v of f.values) L.push(`    ${v.name}: ${fmt(v.value)} ${v.unit}`);
  }
  L.push('', 'DATOS EN VIVO (última lectura)');
  for (const v of r.live ?? []) L.push(`  ${v.name}: ${v.available ? fmt(v.value) + ' ' + v.unit : 'No disponible'}`);
  L.push('', 'DPF — PIDs genéricos SAE (bytes crudos, sin convertir)');
  for (const p of r.dpfGeneric ?? []) L.push(`  ${p.name}: ${p.supported ? (p.raw ?? 'sin respuesta') : 'No disponible'}`);
  L.push('', 'DPF / TRANSMISIÓN — específicos Mercedes');
  for (const p of [...(r.mercedes?.dpf ?? []), ...(r.mercedes?.transmission ?? [])]) L.push(`  ${p.name}: ${p.status}`);
  return L.join('\n');
}

export function download(filename, content, type = 'application/json') {
  const blob = new Blob([content], { type });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
