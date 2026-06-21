// Pito::ThinkingController
//
// While a turn is being processed this:
//   1. animates a Braille spinner, and
//   2. cycles the verb ("doing…" → "computing…" → …) every `interval` ms.
//
// The shown verb is derived from elapsed time since `startedAt` against a shared
// `order` (a shuffled list of indices into `words`). The server uses the same
// formula when it resolves the indicator, so the final past-tense word matches
// the last verb shown — and because it's time-derived, it stays correct across a
// page refresh. The interval is supplied by the server (never hardcoded here).
//
// The backend resolves the indicator by broadcasting a Turbo Stream replace when
// the turn completes.
//
// Data values:
//   frames    — JSON array of Braille chars
//   words     — JSON array of present-tense verbs
//   order     — JSON array of indices into `words`
//   startedAt — turn start, epoch milliseconds
//   interval  — ms each verb stays on screen
//
// Targets:
//   braille — the spinning Braille character span
//   word    — the verb span

import { Controller } from "@hotwired/stimulus"

const BRAILLE_INTERVAL = 80 // ms between Braille frame changes

export default class extends Controller {
  static targets = ["braille", "word"]
  static values = {
    frames: Array,
    words: Array,
    order: Array,
    startedAt: Number,
    interval: Number
  }

  connect() {
    this.#startBraille()
    this.#startWords()
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

  #startWords() {
    if (!this.hasWordTarget || this.orderValue.length === 0 || this.intervalValue <= 0) return
    this.#renderWord()
    this.wordTimer = setInterval(() => this.#renderWord(), this.intervalValue)
  }

  #renderWord() {
    const steps = Math.floor((Date.now() - this.startedAtValue) / this.intervalValue)
    const len = this.orderValue.length
    const idx = this.orderValue[((steps % len) + len) % len]
    const word = this.wordsValue[idx] ?? this.wordsValue[0]
    if (word !== undefined) this.wordTarget.textContent = `${word}…`
  }

  #stop() {
    clearInterval(this.brailleTimer)
    clearInterval(this.wordTimer)
  }
}
