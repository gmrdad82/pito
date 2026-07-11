// pito--pull-refresh
//
// Bottom pull-to-refresh — Brave's top pull, inverted for pito's bottom-anchored
// conversation. ONLY a touch that starts with the scrollback scrolled fully to
// the bottom arms the tracker, and ONLY an upward drag engages: a fixed-position
// spinner tile (Lucide refresh arrow, cloned from the layout's <template>)
// floats in from the bottom edge, tracks the finger 1:1, and its arrow rotates
// with the pulled distance. The moment the tile climbs past THRESHOLD_RATIO of
// the viewport height the reload FIRES (no release needed); letting go earlier
// drops the tile back out. The scrollback content itself never moves.
//
// Gated at connect: enabled in the Hotwire Native shell AND on mobile-web touch
// browsers. Desktop never gets listeners — it has reload buttons and key combos,
// and a bottom-overscroll gesture would fight a trackpad.
//
//   <div id="pito-scrollback" data-controller="… pito--pull-refresh">
//
// Mounted on the scrollback in conversations/show.html.erb AND in the
// home-transition morph (the two must stay in sync).

import { Controller } from "@hotwired/stimulus"

const NATIVE_MARKER = "Hotwire Native"
// The reload fires once the tile has risen this fraction of the viewport height
// above the bottom edge.
const THRESHOLD_RATIO = 0.3
// Arrow rotation per pulled pixel (degrees) — roughly a full turn by the
// threshold on a phone-height viewport, so the arrow visibly "winds up".
const ROTATE_PER_PX = 1.6

export default class extends Controller {
  connect() {
    if (!this.constructor.enabled()) return

    this.startY = null
    this.pull   = 0
    this.fired  = false
    this.abort  = new AbortController()
    const opts  = { signal: this.abort.signal, passive: true }

    this.element.addEventListener("touchstart", (e) => this.#start(e), opts)
    this.element.addEventListener("touchmove",  (e) => this.#move(e),  opts)
    this.element.addEventListener("touchend",   ()  => this.#end(),    opts)
  }

  disconnect() {
    this.abort?.abort()
    this.#spinnerEl()?.remove()
  }

  // Overridable in tests; this gate is the whole feature flag. Enabled in the
  // Hotwire Native shell AND on mobile-web touch browsers. Desktop stays OFF.
  static enabled() {
    const ua = navigator.userAgent
    if (ua.includes(NATIVE_MARKER)) return true
    const touch = (navigator.maxTouchPoints || 0) > 0 || "ontouchstart" in window
    return touch && /Android|iPhone|iPad|iPod|Mobile/i.test(ua)
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
    if (this.startY === null || this.fired) return
    // Only an UPWARD pull (delta > 0) engages. A DOWNWARD gesture is inert.
    this.pull = Math.max(this.startY - event.touches[0].clientY, 0)
    if (this.pull === 0) return this.#park()

    const spinner = this.#spinner()
    if (!spinner) return

    // The tile parks at translate(-50%, 100%) (fully below the edge, CSS) and
    // rises 1:1 with the finger; the arrow winds up with the pulled distance.
    spinner.style.transition = "none"
    spinner.style.transform  = `translate(-50%, calc(100% - ${this.pull}px))`
    const arrow = spinner.querySelector("svg")
    if (arrow) arrow.style.transform = `rotate(${(this.pull * ROTATE_PER_PX).toFixed(1)}deg)`

    if (this.pull >= this.#threshold()) this.#fire(spinner)
  }

  #end() {
    if (this.startY === null) return
    this.startY = null
    this.pull   = 0
    if (!this.fired) this.#park()
  }

  // Reload distance: 30% of the viewport height above the bottom edge.
  #threshold() {
    return (window.innerHeight || 0) * THRESHOLD_RATIO
  }

  // Crossing the threshold fires immediately — no release needed. The arrow
  // switches to a continuous spin (CSS .is-firing) while the reload lands.
  #fire(spinner) {
    this.fired = true
    spinner.querySelector("svg")?.style.removeProperty("transform")
    spinner.classList.add("is-firing")
    this._reload()
  }

  // Drop the tile back below the edge and remove it once the slide finishes
  // (timer fallback for environments without transitions, e.g. jsdom).
  #park() {
    const spinner = this.#spinnerEl()
    if (!spinner) return

    spinner.style.transition = "transform 150ms ease-out"
    spinner.style.transform  = "translate(-50%, 100%)"
    spinner.addEventListener("transitionend", () => spinner.remove(), { once: true })
    setTimeout(() => spinner.remove(), 250)
  }

  // The live tile, if present. Does NOT clone.
  #spinnerEl() {
    return document.querySelector("[data-pull-refresh-spinner]")
  }

  // The tile, cloned lazily from the layout's server-rendered template onto
  // <body> on the first upward pull. Fixed positioning must not sit inside the
  // scrollback (a transformed ancestor would re-anchor it).
  #spinner() {
    const existing = this.#spinnerEl()
    if (existing) return existing

    const template = document.getElementById("pito-pull-refresh-spinner")
    if (!template) return null

    document.body.appendChild(template.content.cloneNode(true))
    return this.#spinnerEl()
  }

  // Seam for tests (location.reload is unstubbable in jsdom).
  _reload() {
    window.location.reload()
  }
}
