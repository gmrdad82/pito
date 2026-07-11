// pito--logo-reveal
//
// The PITO block-logo's broken-neon reveal (start_screen + not_found). Each glyph
// cell (`.pito-logo__cell`) flickers in at its OWN random time (not sequential),
// until all are lit; then random cells get an occasional rare flicker — like a
// faulty neon sign warming up. The flicker visuals live in CSS
// (`.pito-logo.is-revealing`); this controller only schedules the random timing.
//
// Always plays (no fx toggle / reduced-motion respect).
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

const REVEAL_WINDOW_MS = 900  // all cells lit within this window (random per cell)
const FLICKER_LEAD_MS  = 800  // gap after the reveal before the first rare flicker
const FLICKER_MIN_MS   = 2500
const FLICKER_MAX_MS    = 7000
const FLICKER_HOLD_MS  = 280

export default class extends Controller {
  connect() {
    this._timers = []
    this.cells = [...this.element.querySelectorAll(".pito-logo__cell")]
    if (this.cells.length === 0) return

    this.element.classList.add("is-revealing")
    // Each cell lights at a random offset → broken, non-sequential warm-up.
    for (const cell of this.cells) {
      this._timers.push(setTimeout(() => cell.classList.add("lit"), Math.random() * REVEAL_WINDOW_MS))
    }
    this._timers.push(setTimeout(() => this.#flicker(), REVEAL_WINDOW_MS + FLICKER_LEAD_MS))
  }

  disconnect() {
    for (const t of this._timers || []) clearTimeout(t)
    if (this._flickerTimer) clearTimeout(this._flickerTimer)
  }

  // Flicker one random cell, then schedule the next rare flicker.
  #flicker() {
    if (!this.cells || this.cells.length === 0) return

    const cell = this.cells[Math.floor(Math.random() * this.cells.length)]
    cell.classList.add("flicker")
    this._timers.push(setTimeout(() => cell.classList.remove("flicker"), FLICKER_HOLD_MS))

    const next = FLICKER_MIN_MS + Math.random() * (FLICKER_MAX_MS - FLICKER_MIN_MS)
    this._flickerTimer = setTimeout(() => this.#flicker(), next)
  }
}
