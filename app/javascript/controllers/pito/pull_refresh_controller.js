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
// The pane tracks the finger 1:1 and is capped at the gauge block's OWN measured
// height, so pulling slides the conversation UP to uncover EXACTLY the gauge
// (arrows first, ● last) and never over-runs into a blank gap. As it uncovers, a
// continuous `--pull-progress` (0→1) drives the muted→pito-blue fill of the glyphs
// (CSS, background-clip:text) — no per-row stepping, no opacity fade. The reload
// ARMS once the ● disc is fully filled (progress 1) and FIRES on release; a short
// release springs back. The block is intentionally COMPACT so the disc is reachable
// well before mid-screen. FALLBACK_LIFT is used only when offsetHeight is
// unavailable (jsdom under test).
const FALLBACK_LIFT = 160

export default class extends Controller {
  connect() {
    if (!this.constructor.enabled()) return

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

  // Overridable in tests; this gate is the whole feature flag. Enabled in the
  // Hotwire Native shell AND on mobile-web touch browsers (owner: mobile too, not
  // only the APK). Desktop stays OFF — it has reload buttons and key combos, and
  // the bottom-overscroll gesture would fight a trackpad.
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
    this.armed  = false
  }

  #move(event) {
    if (this.startY === null) return
    const delta = this.startY - event.touches[0].clientY
    // Only an UPWARD pull (delta > 0) engages. A DOWNWARD gesture is inert — no
    // lift, no fill, no arm, no parked gap (B1): pull clamps to 0.
    this.pull = Math.max(delta, 0)

    // 1:1 with the finger, capped at the gauge block's own (compact) height —
    // slides the conversation up to uncover exactly the block. Armed once fully
    // uncovered (● disc reached). `progress` (0→1) drives the CSS blue fill.
    const hint     = this.#hint()
    const maxLift  = (hint && hint.offsetHeight) || FALLBACK_LIFT
    const lift     = Math.min(this.pull, maxLift)
    const progress = maxLift > 0 ? lift / maxLift : 0
    this.armed     = this.pull >= maxLift

    this.element.style.transition = "none"
    this.element.style.transform  = this.pull > 0 ? `translateY(-${lift}px)` : ""
    // Cascades to the cloned gauge (a descendant) via CSS custom-property
    // inheritance; the gauge's gradient fills muted→pito-blue by this fraction.
    this.element.style.setProperty("--pull-progress", progress.toFixed(3))

    if (hint) hint.classList.toggle("is-armed", this.armed)
  }

  #end() {
    if (this.startY === null) return
    const armed = this.armed
    this.startY = null
    this.pull   = 0

    if (armed) {
      this._reload()
      return
    }
    // Spring back, and REMOVE the hint from the DOM. It is `display:flex` so an
    // idle opacity:0 block still occupies layout height — leaving it appended left
    // a permanent dead gap at the bottom of the scrollback after any pull (and a
    // bare tap that reached #end used to clone one in). It is re-cloned lazily on
    // the next pull, so the reveal is unaffected. (Do NOT call #hint() here — that
    // clones.)
    this.element.style.transition = "transform 150ms ease-out"
    this.element.style.transform  = ""
    this.element.style.removeProperty("--pull-progress")
    this.element.querySelector("[data-pull-refresh-hint]")?.remove()
  }

  // The shrug indicator, cloned lazily from the layout's server-rendered
  // template into the scrollback's tail on the first pull (copy comes
  // server-resolved from the 50-variant dictionary).
  #hint() {
    let hint = this.element.querySelector("[data-pull-refresh-hint]")
    if (hint) return hint

    const template = document.getElementById("pito-pull-refresh-hint")
    if (!template) return null

    this.element.appendChild(template.content.cloneNode(true))
    return this.element.querySelector("[data-pull-refresh-hint]")
  }

  // Seam for tests (location.reload is unstubbable in jsdom).
  _reload() {
    window.location.reload()
  }
}
