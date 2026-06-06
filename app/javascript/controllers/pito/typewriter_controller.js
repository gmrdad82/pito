// Pito::TypewriterController
//
// Progressively reveals the text content of its `body` target character-by-
// character (typewriter effect) when a segment arrives live over the cable.
//
// EXPERIMENT (full-content reveal):
//   ALL prose targets are animated sequentially in DOM order — body first,
//   then every `prose` target (expand_lines, kv-table key/value spans, section
//   header divs, section row key/value spans).  expand state is ignored so the
//   whole visible card types out regardless of whether expand_all is enabled.
//   Chrome elements (accent bar, hints, meta-line, info-lines) are not tagged
//   as targets and always render instantly.
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
import { fxEnabled } from "pito/settings"
import { TICK_MS, CHARS_TICK } from "pito/typing"

export default class extends Controller {
  static targets = ["body", "prose"]

  connect() {
    if (this.#skipAnimation()) return
    if (!this.hasBodyTarget) return

    const bodyText = this.bodyTarget.textContent
    if (!bodyText) return

    // Guard double-run (e.g. Turbo re-connects same element).
    if (this._connected) return
    this._connected = true
    this._cancelled = false

    // Collect all items to animate in DOM order:
    //   1. the body target (summary prose)
    //   2. every prose target — expand_lines, kv-table key/value spans, section
    //      header divs, section row key/value spans — all in document order.
    // Expand state is intentionally ignored: the whole visible card types out.
    const items = [{ el: this.bodyTarget, text: bodyText }]
    if (this.hasProseTargets) {
      for (const el of this.proseTargets) {
        const text = el.textContent
        if (text) items.push({ el, text })
      }
    }

    // Capture full texts and blank all targets immediately so they appear
    // empty while the job is waiting in the queue.
    this._items = items
    for (const item of items) item.el.textContent = ""

    // Keep a stable cancelled ref for the closure.
    const cancelled = () => this._cancelled

    enqueue(({ instant } = {}) => {
      return new Promise(resolve => {
        // Store the resolver so disconnect() can settle a mid-reveal job and
        // unblock the FIFO (otherwise a removed segment hangs the whole queue).
        this._resolve = () => { this._resolve = null; resolve() }

        if (instant || cancelled()) {
          for (const { el, text } of items) el.textContent = text
          this._resolve()
          return
        }

        let itemIdx = 0
        let pos     = 0

        const tick = () => {
          if (cancelled()) {
            for (const { el, text } of items) el.textContent = text
            this._resolve?.()
            return
          }

          // Advance CHARS_TICK characters, crossing element boundaries as needed.
          let charsLeft = CHARS_TICK
          while (charsLeft > 0 && itemIdx < items.length) {
            const { el, text } = items[itemIdx]
            const remaining = text.length - pos
            if (charsLeft >= remaining) {
              // Finish this element and move to the next.
              el.textContent = text
              charsLeft -= remaining
              itemIdx++
              pos = 0
            } else {
              pos += charsLeft
              el.textContent = text.slice(0, pos)
              charsLeft = 0
            }
          }

          if (itemIdx >= items.length) {
            this._resolve?.()
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

    // Settle any in-flight reveal promise so the shared queue isn't left hanging
    // (a stalled FIFO would stop every later message from typing).
    this._resolve?.()

    // Restore full text so a removed/swapped element isn't left truncated.
    if (this._items) {
      for (const { el, text } of this._items) {
        if (el.isConnected) el.textContent = text
      }
    }
  }

  // ── private ────────────────────────────────────────────────────────────────

  #skipAnimation() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return true
    if (!window.__pitoReady) return true
    if (!fxEnabled()) return true
    return false
  }
}
