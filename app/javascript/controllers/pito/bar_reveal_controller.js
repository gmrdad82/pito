// pito--bar-reveal
//
// The score-bar / TTB fill's OWN reveal — independent of the message fx EFFECT
// (typewriter/scramble/comet). The whole component pops at once (it's in the
// reveal engine's always-pop set); only the `=` fill animates: a left→right clip
// wipe with a comet-style head glow + trailing glow that fades as it sweeps
// (both ride CSS transitions on `.on`; see `.pito-bar-reveal` in application.css).
//
// fx-INDEPENDENT but motion-aware: when decorative motion is off (fx MOTION off
// or prefers-reduced-motion) it does nothing — the fill renders whole.
//
// 20-step stagger: the start is offset by the fill's shared `.pito-shimmer-dN`
// bucket (0..19) so adjacent bars never wipe in sync (same buckets that desync
// the continuous shimmer).
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

const LEAD_IN_MS = 80 // ensure the clipped frame paints before the transition
const STEP_MS    = 35 // per-bucket stagger

export default class extends Controller {
  connect() {

    this.element.classList.add("is-revealing")
    this._raf = requestAnimationFrame(() => {
      this._t = setTimeout(() => this.element.classList.add("on"), LEAD_IN_MS + this.#bucket() * STEP_MS)
    })
  }

  disconnect() {
    if (this._raf) cancelAnimationFrame(this._raf)
    if (this._t) clearTimeout(this._t)
  }

  // The fill's shared stagger bucket (0..19) from its `.pito-shimmer-dN` class.
  #bucket() {
    const m = this.element.className.match(/pito-shimmer-d(\d+)/)
    return m ? parseInt(m[1], 10) : 0
  }
}
