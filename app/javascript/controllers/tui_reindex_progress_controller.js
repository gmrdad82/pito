import { Controller } from "@hotwired/stimulus";

// FB-125 / FB-171 / FB-172 (2026-05-21).
//
// Drives the moving-equals animation of `Tui::ReindexProgressComponent`.
// Frame string is `[` + inner + `]` where inner is exactly `widthValue`
// characters wide (7 to match the letters in "reindex"), containing
// ONLY `=` (1 cell) and `-` (the remaining cells). Total rendered
// width is 9 (`[reindex]`-aligned). The brackets are literal and
// static; only the inner strip animates.
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
