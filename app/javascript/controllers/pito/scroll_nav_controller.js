// pito--scroll-nav
//
// Floating scroll-position pills for the conversation scrollback.
//
// Two fixed pills (top / bottom) float over the conversation column.
// On each scroll tick the controller counts [data-scrollback-message]
// elements that are FULLY above or FULLY below #pito-scrollback's visible
// viewport (using getBoundingClientRect so nested turn containers don't
// confuse offsetTop).
//
// Rules:
//   • Top pill shown iff count-above > 0; bottom pill iff count-below > 0.
//   • On each hidden→visible transition a new random variant is picked from
//     the 50-entry template array.  Top and bottom never share the same
//     index simultaneously.
//   • While the sidebar (#pito-sidebar aside) or the Ctrl+K palette
//     (#pito-command-palette:not(.hidden)) is open, both pills hide.
//     A MutationObserver on both elements restores them when they close.
//   • Ctrl+Home → smooth-scroll to top of scrollback.
//   • Ctrl+End  → smooth-scroll to bottom of scrollback.
//   • The yellow token spans' click actions call jumpTop / jumpBottom.
//
// Markup assumed (rendered by Pito::Shell::ScrollNavComponent):
//   <div data-controller="pito--scroll-nav"
//        data-pito--scroll-nav-variants-value="[...]">
//     <div data-pito--scroll-nav-target="topPill" class="... hidden">
//       <span data-pito--scroll-nav-target="topCount"></span>
//       <span data-action="click->pito--scroll-nav#jumpTop">ctrl+home</span>
//       <span>jump to the start</span>
//     </div>
//     <div data-pito--scroll-nav-target="bottomPill" class="... hidden">
//       <span data-pito--scroll-nav-target="bottomCount"></span>
//       <span data-action="click->pito--scroll-nav#jumpBottom">ctrl+end</span>
//       <span>jump to the end</span>
//     </div>
//   </div>

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["topTemplate", "bottomTemplate"]
  static values  = { variants: Array }

  connect() {
    this.scrollback = document.getElementById("pito-scrollback")
    if (!this.scrollback) return

    // The live pill element for each side (null = not in the DOM) and the variant
    // index currently rendered (-1 = no pill). Pills are CREATED and REMOVED from
    // the DOM — never show/hidden — so their presence alone is the "shown" state.
    this._topEl     = null
    this._bottomEl  = null
    this._topIdx    = -1
    this._bottomIdx = -1

    // rAF throttle flag — one pending update at a time.
    this._rafPending = false

    this._abort = new AbortController()

    // Throttled scroll listener on the scrollback element.
    this.scrollback.addEventListener("scroll", this.#onScroll.bind(this), {
      signal:  this._abort.signal,
      passive: true,
    })

    // Keyboard: Ctrl+Home / Ctrl+End (or Cmd on Mac).
    document.addEventListener("keydown", this.#onKey.bind(this), {
      signal: this._abort.signal,
    })

    // MutationObserver on sidebar + palette so pills hide instantly when
    // either opens and reappear when both close.
    this.#watchOverlays()

    // Re-count when the scrollback CONTENT changes size/shape — a Turbo append or
    // an fx reveal (typewriter / comet) can grow a message's height AFTER the
    // auto-scroll settled, with NO further scroll event to refresh the pills. That
    // left a stale "1 below" lit while already at the bottom (17.15). The rAF
    // throttle in #onScroll coalesces bursts to one #update per frame.
    this._contentObserver = new MutationObserver(this.#onScroll.bind(this))
    this._contentObserver.observe(this.scrollback, {
      childList: true, subtree: true, characterData: true,
    })

    // Initial count — needed for pages where the user loads mid-scroll.
    this.#update()
  }

  disconnect() {
    this._abort?.abort()
    this._overlayObserver?.disconnect()
    this._contentObserver?.disconnect()
    this._topEl?.remove()
    this._bottomEl?.remove()
  }

  // ── Public actions (wired via data-action on yellow tokens) ───────────────

  jumpTop() {
    this.scrollback?.scrollTo({ top: 0, behavior: "smooth" })
  }

  jumpBottom() {
    this.scrollback?.scrollTo({
      top: this.scrollback.scrollHeight,
      behavior: "smooth",
    })
  }

  // ── Private ───────────────────────────────────────────────────────────────

  #onScroll() {
    if (this._rafPending) return
    this._rafPending = true
    requestAnimationFrame(() => {
      this._rafPending = false
      this.#update()
    })
  }

  #onKey(e) {
    const mod = e.ctrlKey || e.metaKey
    if (!mod) return
    if (e.key === "Home") {
      e.preventDefault()
      this.jumpTop()
    } else if (e.key === "End") {
      e.preventDefault()
      this.jumpBottom()
    }
  }

  // Count messages fully outside the viewport; create/remove pills accordingly.
  #update() {
    if (this.#overlaysOpen()) {
      this.#removePill("top")
      this.#removePill("bottom")
      return
    }

    const containerRect = this.scrollback.getBoundingClientRect()
    const { scrollTop, clientHeight, scrollHeight } = this.scrollback

    // EPS absorbs fractional-pixel rounding (devicePixelRatio) and trailing
    // scroll padding so an edge can never leave a stale "1 above/below" pill.
    const EPS = 4

    // Not scrollable — every message fits in the viewport → nothing is above or
    // below; remove BOTH pills (17.2: a short 4-message convo must show neither).
    if (scrollHeight <= clientHeight + EPS) {
      this.#removePill("top")
      this.#removePill("bottom")
      return
    }

    const messages = Array.from(
      this.scrollback.querySelectorAll("[data-scrollback-message]")
    )

    let above = 0
    let below = 0
    for (const el of messages) {
      const r = el.getBoundingClientRect()
      // Tolerance: a message straddling an edge by a sub-pixel is NOT fully out.
      if (r.bottom <= containerRect.top + EPS) above++
      else if (r.top >= containerRect.bottom - EPS) below++
    }

    // Authoritative extremes: at the very top nothing is above; at the very bottom
    // nothing is below. FORCE the count to 0 there so a sub-pixel straddle or the
    // trailing padding spacer can never leave a pill at the edge. At true max
    // scroll `scrollTop + clientHeight === scrollHeight`, so atBottom is reliably
    // true — the stale case is cured by the content MutationObserver re-running.
    const atTop    = scrollTop <= EPS
    const atBottom = scrollTop + clientHeight >= scrollHeight - EPS
    if (atTop) above = 0
    if (atBottom) below = 0

    if (above > 0) this.#ensurePill("top", above)
    else this.#removePill("top")

    if (below > 0) this.#ensurePill("bottom", below)
    else this.#removePill("bottom")
  }

  // Ensure the pill for `side` exists in the DOM — CREATE it (clone the matching
  // <template>, pick a fresh variant, append into the controller root) on first
  // need — then update its count text. The element's presence IS the shown state;
  // there is no show/hide toggle.
  #ensurePill(side, count) {
    let el = side === "top" ? this._topEl : this._bottomEl

    if (!el) {
      // Pick a variant distinct from the opposite pill's current one.
      const oppositeIdx = side === "top" ? this._bottomIdx : this._topIdx
      const idx         = this.#pickVariant(oppositeIdx)
      const template    = side === "top" ? this.topTemplateTarget : this.bottomTemplateTarget
      el = template.content.firstElementChild.cloneNode(true)
      this.element.appendChild(el)
      if (side === "top") { this._topEl = el; this._topIdx = idx }
      else { this._bottomEl = el; this._bottomIdx = idx }
    }

    const idx       = side === "top" ? this._topIdx : this._bottomIdx
    const direction = side === "top" ? "above" : "below"
    const countEl   = el.querySelector("[data-scroll-nav-count]")
    if (countEl) countEl.textContent = this.#format(idx, count, direction)
  }

  // Remove the pill for `side` from the DOM entirely and reset its slot so the
  // next create picks a fresh variant.
  #removePill(side) {
    const el = side === "top" ? this._topEl : this._bottomEl
    if (el) el.remove()
    if (side === "top") { this._topEl = null; this._topIdx = -1 }
    else { this._bottomEl = null; this._bottomIdx = -1 }
  }

  // Interpolate %{count} / %{direction} and resolve {singular|plural} nouns into
  // the chosen variant template. A {a|b} token renders `a` when count is exactly
  // 1, else `b` — so "1 more message above" / "3 more messages above" (17.3/17.6).
  #format(idx, count, direction) {
    const variants = this.variantsValue
    if (!variants.length) return String(count)
    const tmpl = variants[idx] || variants[0]
    return tmpl
      .replace(/%\{count\}/g, count)
      .replace(/%\{direction\}/g, direction)
      .replace(/\{([^|{}]*)\|([^{}]*)\}/g, (_m, singular, plural) =>
        count === 1 ? singular : plural
      )
  }

  // Pick a random variant index, avoiding `exclude` (the opposite pill's index).
  // Falls back after 10 attempts so the loop never spins forever on tiny arrays.
  #pickVariant(exclude) {
    const len = this.variantsValue.length
    if (len === 0) return 0
    if (len === 1) return 0
    let idx
    let attempts = 0
    do {
      idx = Math.floor(Math.random() * len)
      attempts++
    } while (idx === exclude && attempts < 10)
    return idx
  }

  // True when the sidebar panel or the Ctrl+K command palette is open.
  #overlaysOpen() {
    const sidebar = document.getElementById("pito-sidebar")
    const palette = document.getElementById("pito-command-palette")
    const sidebarOpen = !!(sidebar && sidebar.querySelector("aside"))
    const paletteOpen = !!(palette && !palette.classList.contains("hidden"))
    return sidebarOpen || paletteOpen
  }

  // MutationObserver on #pito-sidebar (childList — watches <aside> being added /
  // removed as the panel opens / closes) and on #pito-command-palette (class
  // attribute — watches the `hidden` toggle).  If either element is absent at
  // connect time the observer simply skips it; the real layout always has both
  // in the DOM via application.html.erb.
  // Fires #update() so pills reappear immediately when overlays close rather
  // than waiting for the next scroll event.
  #watchOverlays() {
    const sidebar = document.getElementById("pito-sidebar")
    const palette = document.getElementById("pito-command-palette")

    const refresh = () => this.#update()
    this._overlayObserver = new MutationObserver(refresh)

    if (sidebar) {
      this._overlayObserver.observe(sidebar, { childList: true })
    }
    if (palette) {
      this._overlayObserver.observe(palette, {
        attributes: true,
        attributeFilter: ["class"],
      })
    }
  }
}
