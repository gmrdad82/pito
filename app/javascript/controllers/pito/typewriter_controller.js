// Pito::TypewriterController
//
// Progressively reveals the text content of its `body` target character-by-
// character (typewriter effect) when a segment arrives live over the cable.
//
// Conditions that skip animation (instant full-text):
//   • prefers-reduced-motion media query matches.
//   • window.__pitoReady is falsy (initial server-rendered page load — the
//     controller connects before turbo:load fires, so segments are not live).
//   • The body target has no text content.
//   • opts.instant from the reveal queue (overflow / backpressure).
//
// Scroll-follow:
//   scrollback_controller's MutationObserver watches the scrollback container
//   with { childList: true, subtree: true }.  Setting textContent on a child
//   span triggers childList mutations on that span which bubble through the
//   subtree observer — so scrollback_controller already calls its lock-aware
//   #programmaticScroll() on each tick for free, no extra wiring needed.
//
// Queue:
//   All reveal jobs are serialised through reveal_queue.js (FIFO, backpressure
//   at CAP=3 → instant mode).  Only one segment types at a time, in arrival
//   order.

import { Controller } from "@hotwired/stimulus"
import { enqueue } from "pito/reveal_queue"

const TICK_MS     = 12   // ms per tick
const CHARS_TICK  = 2    // characters per tick (fast reveal)

export default class extends Controller {
  static targets = ["body"]

  connect() {
    if (this.#skipAnimation()) return
    if (!this.hasBodyTarget) return

    const fullText = this.bodyTarget.textContent
    if (!fullText) return

    // Guard double-run (e.g. Turbo re-connects same element).
    if (this._connected) return
    this._connected = true

    this._fullText  = fullText
    this._cancelled = false

    // Blank the span immediately so it appears empty while queued.
    this.bodyTarget.textContent = ""

    // Capture a stable reference to the target for the closure.
    const target    = this.bodyTarget
    const cancelled = () => this._cancelled

    enqueue(({ instant } = {}) => {
      return new Promise(resolve => {
        if (instant || cancelled()) {
          target.textContent = fullText
          resolve()
          return
        }

        let pos = 0

        const tick = () => {
          if (cancelled()) {
            target.textContent = fullText
            resolve()
            return
          }

          pos = Math.min(pos + CHARS_TICK, fullText.length)
          target.textContent = fullText.slice(0, pos)

          if (pos >= fullText.length) {
            resolve()
          } else {
            this._timer = setTimeout(tick, TICK_MS)
          }
        }

        this._timer = setTimeout(tick, TICK_MS)
      })
    })
  }

  disconnect() {
    this._cancelled = true
    clearTimeout(this._timer)

    // Restore full text so a removed/swapped element isn't left truncated.
    if (this._fullText !== undefined && this.hasBodyTarget) {
      this.bodyTarget.textContent = this._fullText
    }
  }

  // ── private ────────────────────────────────────────────────────────────────

  #skipAnimation() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return true
    if (!window.__pitoReady) return true
    return false
  }
}
