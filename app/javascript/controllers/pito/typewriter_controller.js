// Pito::TypewriterController
//
// Progressively reveals the text content of its `body` target character-by-
// character (typewriter effect) when a segment arrives live over the cable.
//
// EXPERIMENT (full-content reveal):
//   ALL prose targets are animated sequentially in DOM order — body first,
//   then every `prose` target (kv-table key/value spans, section header divs,
//   section row key/value spans).
//   HTML targets (e.g. platform logo cells) are interleaved with prose targets
//   in DOM order and revealed at their position in the sequence — no character
//   cost, so they appear in step with their neighbouring text cells rather than
//   instantly on paint.
//   Chrome elements (accent bar, hints, meta-line, info-lines) are not tagged
//   as targets and always render instantly.
//
// Conditions that skip animation (instant full-text):
//   • prefers-reduced-motion media query matches.
//   • window.__pitoReady is falsy (initial server-rendered page load — the
//     controller connects before turbo:load fires, so segments are not live).
//   • There is nothing to reveal (no body text and no prose/htmlProse targets).
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
//
// Completion signal (doneEvent value):
//   When a `doneEvent` value is set, the controller dispatches that document
//   event ONCE when its reveal settles — whether it animated to completion, was
//   instant-mode/backpressured, was cancelled, OR was skipped entirely by a skip
//   guard (reduced-motion / !__pitoReady / fx off / nothing to reveal). The echo
//   segment sets this to `pito:echo-typed` so the comet (pito--dots) can clear
//   the instant the user's echoed input lands — including on the instant path,
//   where no animation runs but the event must still fire.

import { Controller } from "@hotwired/stimulus"
import { enqueue } from "pito/reveal_queue"
import { fxEnabled } from "pito/settings"
import { TICK_MS, CHARS_TICK } from "pito/typing"

export default class extends Controller {
  static targets = ["body", "prose", "htmlProse"]
  static values  = { doneEvent: String }

  connect() {
    if (this.#skipAnimation()) { this.#signalDone(); return }

    // Collect all items to animate in DOM order:
    //   1. the body target (summary prose) — OPTIONAL: html-only cards (game /
    //      video detail, analytics, recommendations, shinies) carry no plain-text
    //      body target, only an htmlProse wrapper revealed via visibility.
    //   2. every prose target — kv-table key/value spans, section header divs,
    //      section row key/value spans — plus every htmlProse target (HTML cells
    //      / whole html cards) — all merged in document order so logos reveal in
    //      step with their neighbouring text cells, not instantly.
    const bodyText = this.hasBodyTarget ? this.bodyTarget.textContent : ""

    const textItems = this.hasProseTarget
      ? this.proseTargets.filter(el => el.textContent).map(el => ({ el, text: el.textContent, html: false }))
      : []
    const htmlItems = this.hasHtmlProseTarget
      ? this.htmlProseTargets.map(el => ({ el, html: true }))
      : []

    // Nothing to reveal — no body text and no prose/html targets. Still settle
    // the completion signal so a waiting comet does not hang on an empty echo.
    if (!bodyText && textItems.length === 0 && htmlItems.length === 0) { this.#signalDone(); return }

    // Guard double-run (e.g. Turbo re-connects same element).
    if (this._connected) return
    this._connected = true
    this._cancelled = false

    // Merge in document order (stable across V8 / SpiderMonkey).
    const mixed = [...textItems, ...htmlItems].sort((a, b) => {
      const rel = a.el.compareDocumentPosition(b.el)
      return rel & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1
    })

    const items = bodyText
      ? [{ el: this.bodyTarget, text: bodyText, html: false }, ...mixed]
      : mixed

    // Capture full texts and blank all targets immediately so they appear
    // empty while the job is waiting in the queue.
    // HTML targets are hidden with visibility so the grid layout is preserved.
    this._items = items
    for (const item of items) {
      if (item.html) item.el.style.visibility = "hidden"
      else item.el.textContent = ""
    }

    // Keep a stable cancelled ref for the closure.
    const cancelled = () => this._cancelled

    enqueue(({ instant } = {}) => {
      return new Promise(resolve => {
        // Store the resolver so disconnect() can settle a mid-reveal job and
        // unblock the FIFO (otherwise a removed segment hangs the whole queue).
        this._resolve = () => { this._resolve = null; this.#signalDone(); resolve() }

        if (instant || cancelled()) {
          for (const item of items) {
            if (item.html) item.el.style.visibility = ""
            else item.el.textContent = item.text
          }
          this._resolve()
          return
        }

        let itemIdx = 0
        let pos     = 0

        const tick = () => {
          if (cancelled()) {
            for (const item of items) {
              if (item.html) item.el.style.visibility = ""
              else item.el.textContent = item.text
            }
            this._resolve?.()
            return
          }

          // Advance CHARS_TICK characters, crossing element boundaries as needed.
          // HTML items (platform logos etc.) are revealed immediately at their
          // position in the sequence — no character cost, no extra delay.
          let charsLeft = CHARS_TICK
          while (charsLeft > 0 && itemIdx < items.length) {
            const item = items[itemIdx]
            if (item.html) {
              item.el.style.visibility = ""
              itemIdx++
              pos = 0
              continue
            }
            const { el, text } = item
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

    // Restore full text / visibility so a removed/swapped element isn't left
    // truncated or hidden.
    if (this._items) {
      for (const item of this._items) {
        if (!item.el.isConnected) continue
        if (item.html) item.el.style.visibility = ""
        else item.el.textContent = item.text
      }
    }
  }

  // ── private ────────────────────────────────────────────────────────────────

  // Dispatch the configured completion event exactly once, when this segment's
  // reveal settles. Fires on EVERY settle path — animated completion, instant /
  // backpressure mode, cancellation, and the skip-guard early returns — so a
  // listener (the comet) never hangs waiting on an animation that did not run.
  // No-op when no doneEvent value was set (every non-echo typewriter mount).
  #signalDone() {
    if (this._doneSignalled) return
    this._doneSignalled = true
    if (!this.doneEventValue) return
    document.dispatchEvent(new CustomEvent(this.doneEventValue, { bubbles: true }))
  }

  #skipAnimation() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return true
    if (!window.__pitoReady) return true
    if (!fxEnabled()) return true
    return false
  }
}
