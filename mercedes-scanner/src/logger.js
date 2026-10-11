// Registro de comandos y respuestas para depuración. El VIN nunca queda en el
// registro: se ocultan las respuestas al 0902 (que traen el VIN en hexadecimal)
// y cualquier texto con forma de VIN (17 caracteres, sin I/O/Q).

const VIN_TEXT = /\b[A-HJ-NPR-Z0-9]{17}\b/g;

export function redact(command, response) {
  let text = String(response ?? '');
  if (command === '0902') {
    const lines = text.split(/\r?\n/).filter(Boolean).length;
    return `[respuesta VIN oculta: ${lines} línea(s)]`;
  }
  return text.replace(VIN_TEXT, '[VIN OCULTO]');
}

export class Logger {
  constructor({ max = 5000, now = () => new Date() } = {}) {
    this.entries = [];
    this.max = max;
    this.now = now;
    this.listeners = new Set();
  }

  add(kind, command, response = '', extra = {}) {
    const entry = {
      t: this.now().toISOString(),
      kind, // 'tx' | 'rx' | 'info' | 'error' | 'blocked'
      command,
      response: redact(command, response),
      ...extra,
    };
    this.entries.push(entry);
    if (this.entries.length > this.max) this.entries.shift();
    for (const l of this.listeners) l(entry);
    return entry;
  }

  onEntry(fn) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  toText() {
    return this.entries
      .map(e => `${e.t} ${e.kind.padEnd(7)} ${e.command ?? ''} ${e.response ? '→ ' + e.response.replace(/\r?\n/g, ' | ') : ''}`.trimEnd())
      .join('\n');
  }
}
