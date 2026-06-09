// Pito::ScrollbackController
//
// Auto-scrolls the scrollback container to the bottom when:
//   (a) the user submits a command (chat-form dispatches "pito:submitted"),
//   (b) a new event segment is appended by Turbo (MutationObserver).
//
// Also binds Shift+ArrowUp / Shift+ArrowDown to page the scrollback up/down
// (global keydown; scrolls ~85% of the viewport height per press).
//
// T21.2 — "Respect scrolled up": if the user has scrolled up more than
// SCROLL_LOCK_THRESHOLD px from the bottom, auto-scroll is suppressed until
// they scroll back down (at which point the lock is released).
//
// Two bugs fixed vs the naive implementation:
//   1. The scroll event listener would misread `scrollTop` during a smooth-scroll
//      animation and incorrectly set `scrollLocked = true`, suppressing the next
//      cable message's scroll.  A `#programmaticScroll()` wrapper sets a flag
//      that tells the listener to ignore events we triggered ourselves.
//   2. `scrollHeight` is read before the browser has painted the new element's
//      full height.  A `requestAnimationFrame` pass re-scrolls after layout.
//
// Usage:
//   <div id="pito-scrollback" data-controller="pito--scrollback">

import { Controller } from "@hotwired/stimulus"

const SCROLL_LOCK_THRESHOLD = 80   // px from bottom before user scroll locks auto-scroll
const SMOOTH_SCROLL_GRACE   = 600  // ms to consider a scroll programmatic (covers animation)

export default class extends Controller {
  connect() {
    this.scrollLocked          = false
    this.programmaticScrolling = false
    this.lastScrollTop         = null
    this.#programmaticScroll({ instant: true })
    this.#bindScroll()
    this.#bindMutation()
    this.#bindSubmit()
    this.#bindKeyScroll()
  }

  disconnect() {
    this.abort?.abort()
    this.mutationObserver?.disconnect()
    clearTimeout(this.scrollGraceTimer)
  }

  // ── internals ──────────────────────────────────────────────────────────────

  // Scroll to bottom and mark the scroll as programmatic so the scroll event
  // listener ignores the intermediate positions during the animation.
  #programmaticScroll({ instant = false } = {}) {
    if (this.scrollLocked) return

    this.programmaticScrolling = true
    clearTimeout(this.scrollGraceTimer)

    this.element.scrollTo({
      top: this.element.scrollHeight,
      behavior: instant ? "instant" : "smooth",
    })

    // Clear the flag after the smooth animation finishes (600ms grace covers it).
    this.scrollGraceTimer = setTimeout(() => {
      this.programmaticScrolling = false
    }, instant ? 0 : SMOOTH_SCROLL_GRACE)
  }

  // Only update scrollLocked from MANUAL user scrolls, not our own animations.
  // During a programmatic scroll we still honour upward movement — if the user
  // grabs the scrollbar while we're animating downward, we cancel the lock and
  // set scrollLocked immediately.  Downward events during animation are ignored.
  #bindScroll() {
    this.abort = new AbortController()
    this.element.addEventListener("scroll", () => {
      const scrollTop    = this.element.scrollTop
      const movingUp     = this.lastScrollTop !== null && scrollTop < this.lastScrollTop
      this.lastScrollTop = scrollTop

      if (this.programmaticScrolling) {
        if (movingUp) {
          // User interrupted our animation — honour their scroll intent.
          this.programmaticScrolling = false
          clearTimeout(this.scrollGraceTimer)
          this.scrollLocked = true
        }
        return
      }

      const distanceFromBottom =
        this.element.scrollHeight - scrollTop - this.element.clientHeight
      this.scrollLocked = distanceFromBottom > SCROLL_LOCK_THRESHOLD
    }, { signal: this.abort.signal, passive: true })
  }

  // Watch for Turbo appending new children (broadcast events).
  // Dispatches `pito:echo-appended` / `pito:result-appended` so other
  // controllers (pito--dots) can react to the segment type.
  // Scrolls immediately, then once more after the next frame so any
  // height that settles after paint is also captured.
  #bindMutation() {
    this.mutationObserver = new MutationObserver(mutations => {
      for (const { addedNodes } of mutations) {
        for (const node of addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue
          const isEcho = !!node.querySelector?.('[data-accent="purple"]')
          document.dispatchEvent(new CustomEvent(
            isEcho ? "pito:echo-appended" : "pito:result-appended"
          ))
          // Cover art (game detail message) loads AFTER this scroll fires and
          // grows the segment height, leaving the scroll stuck mid-image. Re-
          // scroll once each late-loading image settles so the newest message
          // (e.g. the Enhanced one) ends up fully in view.
          this.#rescrollOnImageLoad(node)
        }
      }
      // Scroll now (catches most segments) + after layout (catches variable-height ones).
      this.#programmaticScroll()
      requestAnimationFrame(() => this.#programmaticScroll())
    })
    // subtree: true because results append INTO per-turn containers (nested),
    // not as direct children of the scrollback.
    this.mutationObserver.observe(this.element, { childList: true, subtree: true })
  }

  // Re-scroll to bottom once each not-yet-loaded image inside `node` finishes
  // loading. Honours scrollLocked (won't yank a user who scrolled up).
  #rescrollOnImageLoad(node) {
    const imgs = []
    if (node.tagName === "IMG") imgs.push(node)
    node.querySelectorAll?.("img").forEach(img => imgs.push(img))

    for (const img of imgs) {
      if (img.complete) continue
      const rescroll = () => this.#programmaticScroll()
      img.addEventListener("load",  rescroll, { once: true, signal: this.abort.signal })
      img.addEventListener("error", rescroll, { once: true, signal: this.abort.signal })
    }
  }

  // Shift+ArrowUp / Shift+ArrowDown page the scrollback up/down. Global so it
  // works regardless of focus; we deliberately scroll directly (not via
  // #programmaticScroll) so the natural scroll listener updates scrollLocked —
  // paging up locks auto-scroll, paging back to the bottom releases it.
  #bindKeyScroll() {
    window.addEventListener("keydown", (e) => {
      if (!e.shiftKey) return
      if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return

      e.preventDefault()
      const step = Math.round(this.element.clientHeight * 0.85)
      this.element.scrollBy({ top: e.key === "ArrowUp" ? -step : step, behavior: "smooth" })
    }, { signal: this.abort.signal })
  }

  // On submit always unlock + scroll (the user just acted).
  #bindSubmit() {
    document.addEventListener("pito:submitted", () => {
      this.scrollLocked = false
      this.#programmaticScroll()
    }, { signal: this.abort.signal })
  }
}
