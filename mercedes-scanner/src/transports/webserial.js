// Transporte real: adaptador USB (puerto serie) mediante Web Serial.
// Requiere Chrome o Edge en macOS y la página servida desde localhost o https.

export class WebSerialTransport {
  constructor({ baudRate = 38400 } = {}) {
    this.kind = 'real';
    this.baudRate = baudRate;
    this.port = null;
    this.reader = null;
    this.dataCb = () => {};
    this.lostCb = () => {};
    this.closing = false;
  }

  static isSupported() {
    return typeof navigator !== 'undefined' && 'serial' in navigator;
  }

  onData(cb) { this.dataCb = cb; }
  onDisconnect(cb) { this.lostCb = cb; }

  async open() {
    this.port = await navigator.serial.requestPort();
    await this.port.open({ baudRate: this.baudRate });
    this.closing = false;
    navigator.serial.addEventListener('disconnect', this._onUnplug = e => {
      if (e.target === this.port) this.lostCb();
    });
    this._readLoop();
  }

  portInfo() {
    const i = this.port?.getInfo?.() ?? {};
    const h = n => (n === undefined ? '?' : '0x' + n.toString(16).padStart(4, '0'));
    return { usbVendorId: h(i.usbVendorId), usbProductId: h(i.usbProductId), baudRate: this.baudRate };
  }

  async _readLoop() {
    const decoder = new TextDecoder();
    try {
      while (this.port?.readable && !this.closing) {
        this.reader = this.port.readable.getReader();
        try {
          for (;;) {
            const { value, done } = await this.reader.read();
            if (done) break;
            this.dataCb(decoder.decode(value, { stream: true }));
          }
        } finally {
          this.reader.releaseLock();
        }
      }
    } catch {
      if (!this.closing) this.lostCb();
    }
  }

  async write(text) {
    const writer = this.port.writable.getWriter();
    try {
      await writer.write(new TextEncoder().encode(text));
    } finally {
      writer.releaseLock();
    }
  }

  async close() {
    this.closing = true;
    navigator.serial.removeEventListener('disconnect', this._onUnplug);
    try { await this.reader?.cancel(); } catch { /* */ }
    try { await this.port?.close(); } catch { /* */ }
    this.port = null;
  }
}
