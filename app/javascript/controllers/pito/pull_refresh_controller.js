// pito--pull-refresh
//
// Bottom pull-to-refresh — Android shell ONLY (G74). pito's conversation
// lives at the BOTTOM of the scrollback, so the refresh gesture mirrors
// Slack's: overscroll past the bottom edge and release. Top pull-to-refresh
// stays deliberately OFF in the shell's path configuration (the gesture
// fights scrolling the history); this is its bottom-anchored replacement —
// and the shell's only manual refresh affordance besides tapping the nudge.
//
// Gated on the Hotwire Native UA at connect: browsers (desktop AND mobile)
// never get listeners — they have reload buttons and key combos.
//
// Mechanics: a touch that starts with the scrollback already at the bottom
// arms the tracker; dragging UP from there is an overscroll (the pane can't
// scroll further), fed back as a small translateY lift; releasing past
// THRESHOLD_PX hard-reloads (location.reload — a Turbo visit would not
// refetch updated CSS/JS, and this gesture's other job is post-update
// recovery). Releasing short of it springs back.
//
//   <div id="pito-scrollback" data-controller="… pito--pull-refresh">
//
// Mounted on the scrollback in conversations/show.html.erb AND in the
// home-transition morph (the two must stay in sync — G12/G66).

import { Controller } from "@hotwired/stimulus"

const NATIVE_MARKER = "Hotwire Native"
const THRESHOLD_PX  = 90   // pull distance that arms the reload
const MAX_LIFT_PX   = 40   // visual cap — the pane lifts at most this much

export default class extends Controller {
  connect() {
    if (!this.constructor.nativeShell()) return

    this.startY = null
    this.pull   = 0
    this.abort  = new AbortController()
    const opts  = { signal: this.abort.signal, passive: true }

    this.element.addEventListener("touchstart", (e) => this.#start(e), opts)
    this.element.addEventListener("touchmove",  (e) => this.#move(e),  opts)
    this.element.addEventListener("touchend",   ()  => this.#end(),    opts)
  }

  disconnect() {
    this.abort?.abort()
  }

  // Overridable in tests; the UA gate is the whole feature flag.
  static nativeShell() {
    return navigator.userAgent.includes(NATIVE_MARKER)
  }

  #atBottom() {
    const el = this.element
    return el.scrollTop + el.clientHeight >= el.scrollHeight - 2
  }

  #start(event) {
    this.startY = this.#atBottom() ? event.touches[0].clientY : null
    this.pull   = 0
  }

  #move(event) {
    if (this.startY === null) return
    const delta = this.startY - event.touches[0].clientY
    this.pull = Math.max(delta, 0)

    const lift = Math.min(this.pull / 3, MAX_LIFT_PX)
    this.element.style.transition = "none"
    this.element.style.transform  = this.pull > 0 ? `translateY(-${lift}px)` : ""
  }

  #end() {
    if (this.startY === null) return
    const armed = this.pull >= THRESHOLD_PX
    this.startY = null

    if (armed) {
      this._reload()
      return
    }
    // Spring back
    this.element.style.transition = "transform 150ms ease-out"
    this.element.style.transform  = ""
  }

  // Seam for tests (location.reload is unstubbable in jsdom).
  _reload() {
    window.location.reload()
  }
}
