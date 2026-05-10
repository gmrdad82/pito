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
export default class extends Controller {
  static values = {
    frames: Array,
    interval: { type: Number, default: 200 }
  }

  connect() {
    this.frame = 0
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
