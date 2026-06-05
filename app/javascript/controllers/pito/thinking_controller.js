// Pito::ThinkingController
//
// Animates a Braille spinner while a turn is being processed.
// The word is rendered server-side and never changes.
// The backend resolves the indicator by broadcasting a Turbo Stream replace
// when the turn completes.
//
// Data attribute:
//   data-pito--thinking-frames-value — JSON array of Braille chars
//
// Target:
//   braille — the spinning Braille character span

import { Controller } from "@hotwired/stimulus"

const BRAILLE_INTERVAL = 80 // ms between Braille frame changes

export default class extends Controller {
  static targets = ["braille"]
  static values = {
    frames: Array
  }

  connect() {
    this.#startBraille()
  }

  disconnect() {
    this.#stop()
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #startBraille() {
    this.brailleIdx = 0
    this.brailleTimer = setInterval(() => {
      this.brailleIdx = (this.brailleIdx + 1) % this.framesValue.length
      this.brailleTarget.textContent = this.framesValue[this.brailleIdx]
    }, BRAILLE_INTERVAL)
  }

  #stop() {
    clearInterval(this.brailleTimer)
  }
}
