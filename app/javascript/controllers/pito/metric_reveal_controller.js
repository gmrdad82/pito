// pito--metric-reveal
//
// BASE / ENGINE for the analytics metric reveal animation. Every bespoke metric
// component (Views first; heatmap/retention/… later) mounts a controller that
// EXTENDS this one and overrides `animate()` with its own appear choreography,
// reusing the shared lifecycle + primitives here.
//
// Lifecycle (fail-open): on connect, if decorative motion is suppressed (fx off
// via /config, or prefers-reduced-motion) we do NOTHING — the chart was rendered
// whole and the hidden CSS states only apply under `.is-revealing`. Otherwise we
// add `.is-revealing` (which arms the hidden clip-paths) and, on the next frame,
// run `animate()`.
//
// Primitives the subclass composes:
//   revealRows({leadIn, cadence}) — add `.on` to the row targets BOTTOM→UP, after
//                                   a lead-in, one every `cadence` ms
//   schedule(fn, ms) / wait(ms)   — tracked timers (all cleared on disconnect)
//
// The default animate() pops every row at once (a sane base); subclasses
// sequence (Views wipes bottom→up).
//
// Auto-registered via eagerLoadControllersFrom — registered but only mounted
// through its concrete subclasses (no element uses `pito--metric-reveal`).

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["plot", "row"]

  connect() {
    this._timers = []

    this.element.classList.add("is-revealing")
    this._raf = requestAnimationFrame(() => this.animate())
  }

  disconnect() {
    if (this._raf) cancelAnimationFrame(this._raf)
    ;(this._timers || []).forEach(clearTimeout)
  }

  // Base default: pop every row at once. Subclasses override to choreograph.
  async animate() {
    this.rowTargets.forEach((r) => r.classList.add("on"))
  }

  // Reveal the rows BOTTOM→UP (the chart fills upward from the baseline), after a
  // lead-in, one `.on` every `cadence` ms.
  revealRows({ leadIn = 300, cadence = 130 } = {}) {
    const rows = [...this.rowTargets].reverse() // bottom row first
    rows.forEach((r, k) => this.schedule(() => r.classList.add("on"), leadIn + k * cadence))
  }

  schedule(fn, ms) {
    const id = setTimeout(fn, ms)
    this._timers.push(id)
    return id
  }

  wait(ms) {
    return new Promise((resolve) => this.schedule(resolve, ms))
  }
}
