import { Controller } from "@hotwired/stimulus";

const FRAME_MS = 120; // cadence of the `=` moving across

export default class extends Controller {
  static values = { width: { type: Number, default: 7 }, brand: String };

  connect() {
    this.frame = 0;
    this.tick = setInterval(() => this.advance(), FRAME_MS);
  }

  disconnect() {
    if (this.tick) clearInterval(this.tick);
  }

  advance() {
    this.frame = (this.frame + 1) % this.widthValue;
    const before = "-".repeat(this.frame);
    const after = "-".repeat(this.widthValue - this.frame - 1);
    this.element.textContent = `[${before}=${after}]`;
  }
}
