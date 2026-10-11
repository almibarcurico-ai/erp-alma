// Lectura e interpretación prudente del VIN.
// No se deduce motor ni versión: en Mercedes-Benz eso se confirma con la
// "datacard" del vehículo (concesionario / EPC) a partir del VIN completo.

const WMI = {
  WDB: 'Mercedes-Benz',
  WDC: 'Mercedes-Benz (SUV / todoterreno)',
  WDD: 'Mercedes-Benz (turismos)',
  W1K: 'Mercedes-Benz (turismos)',
  W1N: 'Mercedes-Benz (SUV)',
};

export function asciiFromBytes(bytes) {
  return bytes.filter(b => b >= 0x20 && b < 0x7f).map(b => String.fromCharCode(b)).join('').trim();
}

// Respuesta CAN al 0902: [0x49, 0x02, 0x01, ...17 bytes ASCII]
export function parseVinMessage(data) {
  if (data[0] !== 0x49 || data[1] !== 0x02) return null;
  const vin = asciiFromBytes(data.slice(3));
  return /^[A-HJ-NPR-Z0-9]{17}$/.test(vin) ? vin : null;
}

export function maskVin(vin) {
  if (!vin) return vin;
  return vin.slice(0, 3) + '*'.repeat(vin.length - 7) + vin.slice(-4);
}

export function describeVin(vin) {
  if (!vin) return null;
  const wmi = vin.slice(0, 3);
  const maker = WMI[wmi] ?? 'Fabricante no reconocido por la app';
  const isMercedes = wmi in WMI;
  return {
    vin,
    wmi,
    maker,
    // En los VIN Mercedes, las posiciones 4–9 suelen corresponder al
    // "Baumuster" (p. ej. 156xxx para la serie X156). Es indicativo: el motor
    // exacto debe confirmarse con la datacard.
    series: isMercedes ? vin.slice(3, 6) : null,
    baumuster: isMercedes ? vin.slice(3, 9) : null,
    isX156: isMercedes ? vin.slice(3, 6) === '156' : null,
    engineNote: 'Motor y versión: confirmar con la datacard Mercedes-Benz del VIN (no se deducen en la app).',
  };
}
