// Funciones específicas Mercedes-Benz (etapa 3).
//
// Estado: NO HAY DATOS ESPECÍFICOS VERIFICADOS. Los parámetros de abajo están
// en la ECU del motor (CDI) y en el TCU de la transmisión automática (en el GLA X156 normalmente 7G-DCT; confirmar con la datacard). Se leen con
// diagnóstico UDS (ISO 14229, servicio 0x22 ReadDataByIdentifier) usando
// identificadores (DIDs) y direcciones propietarios de Mercedes-Benz. Esos
// identificadores no son públicos. Están en los archivos de descripción de
// Xentry/DTS (CBF/SMR-D/ODX). Mientras no exista una fuente verificable, cada
// parámetro se informa como "No disponible" y la app NO envía ninguna petición
// UDS: la lista blanca de safety.js las bloquea.
//
// Para agregar un parámetro verificado, añade una entrada con `source`
// (documento y versión), `ecuRequestId`, `ecuResponseId`, `did` y `decode`,
// y amplía la lista blanca solo para ese `22 xx xx` concreto.

export const MERCEDES_DPF_PARAMS = [
  { key: 'diffPressure', name: 'Presión diferencial del DPF', kind: 'medido (sensor)' },
  { key: 'sootLoad', name: 'Carga de hollín calculada', kind: 'estimación de la ECU' },
  { key: 'ashLoad', name: 'Carga de cenizas estimada', kind: 'estimación de la ECU' },
  { key: 'egt', name: 'Temperaturas de escape (antes/después del DPF)', kind: 'medido (sensores)' },
  { key: 'regenStatus', name: 'Estado de regeneración', kind: 'estado de la ECU' },
  { key: 'sinceRegen', name: 'Distancia/tiempo desde la última regeneración', kind: 'contador de la ECU' },
];

export const MERCEDES_TRANSMISSION_PARAMS = [
  { key: 'tcuDtcs', name: 'Códigos propios del TCU' },
  { key: 'gear', name: 'Marcha actual / objetivo' },
  { key: 'oilTemp', name: 'Temperatura del aceite de la transmisión' },
  { key: 'paddleUp', name: 'Señal de la paleta + (subir)' },
  { key: 'paddleDown', name: 'Señal de la paleta − (bajar)' },
];

// Registro de definiciones verificadas. Vacío a propósito.
export const VERIFIED_DIDS = [];

export function mercedesCapabilities({ dpfGeneric = [], ecus = [] } = {}) {
  const genericDpfSupported = dpfGeneric.filter(p => p.supported).map(p => p.name);
  const reason = 'Requiere diagnóstico específico Mercedes-Benz (UDS con identificadores propietarios). No hay una fuente verificable cargada en la app.';
  return {
    dpf: MERCEDES_DPF_PARAMS.map(p => ({
      ...p,
      value: null,
      status: 'No disponible',
      reason,
    })),
    dpfGenericSupported: genericDpfSupported,
    transmission: MERCEDES_TRANSMISSION_PARAMS.map(p => ({
      ...p,
      value: null,
      status: 'No disponible',
      reason: p.key === 'tcuDtcs' && ecus.length > 1
        ? 'Hay más de una ECU respondiendo a OBD-II genérico. Sus códigos de emisiones aparecen en la sección de códigos, pero los códigos propios del TCU requieren diagnóstico Mercedes.'
        : reason,
    })),
    hardwareNeeded: [
      'Interfaz Mercedes-Benz SD Connect C4/C5/C6 (o compatible DoIP/CAN) con Xentry y su licencia: es la vía oficial y lee todos los módulos, incluidos el TCU y las paletas.',
      'Alternativa: una interfaz J2534 con software que tenga cobertura Mercedes verificada para la serie 156.',
      'Para extender esta app: un adaptador STN (OBDLink SX/EX) es más confiable que un clon ELM327 para ISO-TP con direccionamiento propio, pero no aporta los identificadores Mercedes. Esos deben venir de documentación verificable.',
    ],
  };
}
