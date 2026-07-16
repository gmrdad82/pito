// Pito::ScrollbackController
//
// The scrollback NEVER scrolls on its own (owner 2026-07-13: the AI
// answer's tool-iteration updates kept yanking the view mid-read — the
// whole follow-the-newest feature is purged; ctrl+home / ctrl+end pills
// are the navigation). Exactly TWO scrolls remain, both user-initiated:
//
//   1. Page load / conversation resume — jump instantly to the end, the
//      newest message (owner: "when I reload or resume I wanna jump
//      straight to its end").
//   2. Submitting a command (chat-form dispatches "pito:submitted") — the
//      user just acted; show them their own message landing.
//
// The MutationObserver survives ONLY as an event bus: pito--dots and
// friends rely on pito:echo-appended / pito:result-appended. It scrolls
// nothing.
//
// Shift+ArrowUp / Shift+ArrowDown page the scrollback (~85% viewport per
// press), global keydown.
//
// Usage:
//   <div id="pito-scrollback" data-controller="pito--scrollback">

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.abort = new AbortController()
    // (1) Resume at the end — instant, before paint matters. EXCEPT when the
    // URL carries an #event_<id> anchor (resume-to-a-specific-event, e.g.
    // /resume <uuid> <event_id>): pito--anchor-jump owns the scroll position
    // then, and this jump-to-end must not yank focus away from it.
    if (!this.#hasEventAnchor()) {
      this.#jumpToEnd()
      // Late-settling layout (fonts, first images) can grow the scrollback
      // right after load; one follow-up jump next frame keeps "the end"
      // honest. This is still the LOAD jump, not a follow feature.
      requestAnimationFrame(() => this.#jumpToEnd())
    }
    this.#bindMutationBus()
    this.#bindSubmit()
    this.#bindKeyScroll()
  }

  disconnect() {
    this.abort?.abort()
    this.mutationObserver?.disconnect()
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #jumpToEnd() {
    this.element.scrollTo({ top: this.element.scrollHeight, behavior: "instant" })
  }

  // True when the URL hash targets a specific event (resume-to-anchor). The
  // pito--anchor-jump controller owns scroll position in that case.
  #hasEventAnchor() {
    return /^#event_\d+$/.test(window.location.hash)
  }

  // Event bus ONLY (owner purge): announces appended segments for the
  // dots/sound controllers. No scrolling here, ever.
  #bindMutationBus() {
    this.mutationObserver = new MutationObserver(mutations => {
      for (const { addedNodes } of mutations) {
        for (const node of addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue
          const isEcho = !!node.querySelector?.('[data-accent="purple"]')
          document.dispatchEvent(new CustomEvent(
            isEcho ? "pito:echo-appended" : "pito:result-appended"
          ))
        }
      }
    })
    // subtree: true because results append INTO per-turn containers (nested),
    // not as direct children of the scrollback.
    this.mutationObserver.observe(this.element, { childList: true, subtree: true })
  }

  // Shift+ArrowUp / Shift+ArrowDown page the scrollback up/down. Global so
  // it works regardless of focus.
  #bindKeyScroll() {
    window.addEventListener("keydown", (e) => {
      if (!e.shiftKey) return
      if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return

      e.preventDefault()
      const step = Math.round(this.element.clientHeight * 0.85)
      this.element.scrollBy({ top: e.key === "ArrowUp" ? -step : step, behavior: "smooth" })
    }, { signal: this.abort.signal })
  }

  // (2) The user just sent a command — show it landing. The one scroll
  // that reacts to content, because the user caused the content.
  #bindSubmit() {
    document.addEventListener("pito:submitted", () => {
      this.#jumpToEnd()
    }, { signal: this.abort.signal })
  }
}
