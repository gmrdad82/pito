import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish (2026-05-10) — animated text indicator for
// in-flight IGDB resyncs on the game show page. Cycles a 4-frame
// dash sequence in place of the `[resync]` link while the server
// flag `games.resyncing` is true.
//
// Frames and interval ms come from data attributes so the same
// controller can be repurposed for other slow operations.
//
// Pairs with `auto-refresh` controller — the show page polls
// every ~5s while resyncing so the link flips back automatically
// when the Sidekiq job clears the flag.
//
// 2026-05-19 (Wave B) — `phaseOffset` value lets multiple
// concurrent indicators on /games/:id (genre line, kv-table date /
// dev / pub rows, summary block) start at different positions in
// the cycle so the page doesn't read as a single uniform pulse.
// Default 0 = current behavior. The initial frame index is set to
// `phaseOffsetValue % framesValue.length` so callers can stagger
// their loaders by passing offsets 0, 1, 2, 3 (etc).
export default class extends Controller {
  static values = {
    frames: Array,
    interval: { type: Number, default: 200 },
    phaseOffset: { type: Number, default: 0 }
  }

  connect() {
    const length = this.framesValue.length
    this.frame = length > 0 ? this.phaseOffsetValue % length : 0
    this.tick()
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  tick() {
    if (this.framesValue.length === 0) return
    this.element.textContent =
      this.framesValue[this.frame % this.framesValue.length]
    this.frame++
  }
}
