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

// Tailwind's `hidden` class — added to hide a pill, removed to show it.
// The base .pito-scroll-nav__pill CSS sets display:flex so removing `hidden`
// is all that is needed to reveal it.
const HIDDEN = "hidden"

export default class extends Controller {
  static targets = ["topPill", "bottomPill", "topCount", "bottomCount"]
  static values  = { variants: Array }

  connect() {
    this.scrollback = document.getElementById("pito-scrollback")
    if (!this.scrollback) return

    // Variant index currently shown for each pill (-1 = pill is hidden).
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

    // Initial count — needed for pages where the user loads mid-scroll.
    this.#update()
  }

  disconnect() {
    this._abort?.abort()
    this._overlayObserver?.disconnect()
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

  // Count messages fully outside the viewport; show/hide pills accordingly.
  #update() {
    if (this.#overlaysOpen()) {
      this.#hidePill("top")
      this.#hidePill("bottom")
      return
    }

    const containerRect = this.scrollback.getBoundingClientRect()
    const { scrollTop, clientHeight, scrollHeight } = this.scrollback

    // EPS absorbs fractional-pixel rounding (devicePixelRatio) and trailing
    // scroll padding so an edge can never leave a stale "1 above/below" pill.
    const EPS = 4

    // Not scrollable — every message fits in the viewport → nothing is above or
    // below; hide BOTH pills (17.2: a short 4-message convo must show neither).
    if (scrollHeight <= clientHeight + EPS) {
      this.#hidePill("top")
      this.#hidePill("bottom")
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

    // Authoritative extremes (17.3/17.6): at the very top nothing is above; at
    // the very bottom nothing is below. FORCE the count to 0 there so a sub-pixel
    // straddle or the scrollback's trailing padding spacer can never keep a pill
    // lit at the edge — the count, not just the show-condition, drops to 0.
    const atTop    = scrollTop <= EPS
    const atBottom = scrollTop + clientHeight >= scrollHeight - EPS
    if (atTop) above = 0
    if (atBottom) below = 0

    if (above > 0) {
      this.#showPill("top", above)
    } else {
      this.#hidePill("top")
    }

    if (below > 0) {
      // 17.2c: anchor the bottom pill flush to the BOTTOM of the scrollback —
      // which is the TOP of the context bar directly beneath it — so it touches
      // the context bar with no gap. documentElement.clientHeight is the stable
      // layout viewport (unaffected by mobile browser chrome).
      const viewportH = document.documentElement.clientHeight
      this.bottomPillTarget.style.bottom = `${Math.max(0, viewportH - containerRect.bottom)}px`
      this.#showPill("bottom", below)
    } else {
      this.#hidePill("bottom")
    }
  }

  // Show a pill: pick a new variant on hidden→visible, then interpolate + render.
  #showPill(side, count) {
    const pill     = side === "top" ? this.topPillTarget    : this.bottomPillTarget
    const countEl  = side === "top" ? this.topCountTarget   : this.bottomCountTarget
    const isHidden = side === "top" ? this._topIdx === -1   : this._bottomIdx === -1

    if (isHidden) {
      // Pick a new variant; must not duplicate the opposite pill's current index.
      const oppositeIdx = side === "top" ? this._bottomIdx : this._topIdx
      const newIdx      = this.#pickVariant(oppositeIdx)
      if (side === "top") this._topIdx = newIdx
      else this._bottomIdx = newIdx
    }

    const idx       = side === "top" ? this._topIdx    : this._bottomIdx
    const direction = side === "top" ? "above"         : "below"
    countEl.textContent = this.#format(idx, count, direction)

    pill.classList.remove(HIDDEN)
  }

  // Hide a pill and reset its variant slot so the next show picks a fresh one.
  #hidePill(side) {
    const pill = side === "top" ? this.topPillTarget : this.bottomPillTarget
    pill.classList.add(HIDDEN)
    if (side === "top") this._topIdx = -1
    else this._bottomIdx = -1
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
