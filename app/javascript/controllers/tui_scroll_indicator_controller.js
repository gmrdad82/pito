import { Controller } from "@hotwired/stimulus"

/**
 * tui-scroll-indicator — toggles the top/bottom ▲/▼ overlay glyphs and
 * positions a floating █ handle on the right border, based on scroll position.
 *
 * Visibility rules:
 *   - ▲ visible when scrollTop > THRESHOLD_PX (content above is hidden)
 *   - ▼ visible when scrollTop + clientHeight < scrollHeight - THRESHOLD_PX
 *     (content below is hidden)
 *   - Neither visible when content does not overflow OR scrolled exactly
 *     to the corresponding edge.
 *   - Handle visible whenever content overflows (max > THRESHOLD_PX);
 *     positioned in pixels via `style.top = <Npx>` directly. The
 *     usable handle track reserves ARROW_OFFSET_PX at the top + bottom
 *     so the █ handle never overlaps the ▲ ▼ arrow glyphs (2026-05-24).
 *
 * Recomputed on:
 *   - connect (initial paint)
 *   - scroll event (throttled via requestAnimationFrame)
 *   - resize event (via ResizeObserver)
 *
 * Scroll target (FB-SCROLL-CLIP 2026-05-24):
 *   When a `scroll` target element is present (e.g., the inner
 *   `.tui-panel-fieldset__scroll` wrapper div that owns `overflow-y: auto`
 *   while the fieldset itself stays `overflow: visible`), the controller
 *   attaches its scroll + resize listeners to that inner element rather
 *   than `this.element`. This allows the fieldset to remain
 *   `overflow: visible` so the absolutely-positioned indicator glyphs
 *   at `right: -7px` are not clipped by the fieldset's own overflow box.
 *   If no `scroll` target is registered, falls back to `this.element`
 *   for backwards compatibility with standalone usage.
 *
 * The indicators are pointer-events: none — purely visual hints. Scroll
 * itself is mouse-wheel + keyboard cursor (j/k) handled elsewhere.
 */
export default class extends Controller {
  static targets = ["top", "bottom", "handle", "scroll"]
  static THRESHOLD_PX = 2
  // 2026-05-24 — Reserve N px at the top + bottom of the scroll track so
  // the █ handle glyph never overlaps the ▲ / ▼ arrow glyphs. ▲ is at
  // `top: 2px` with a ~13px-tall glyph box → arrow occupies y=2..15.
  // Adding ~5px breathing room → handle USABLE zone starts at y=20px.
  // Same offset reserved at the bottom (▼ at `bottom: 2px`).
  static ARROW_OFFSET_PX = 20

  connect() {
    // Prefer inner scroll target (fieldset wrapper) over this.element so
    // the fieldset can stay overflow: visible and the indicators are not clipped.
    const scrollEl = this.hasScrollTarget ? this.scrollTarget : this.element
    this._scrollEl = scrollEl
    this._boundCompute = this.requestCompute.bind(this)
    this._raf = null
    scrollEl.addEventListener("scroll", this._boundCompute, { passive: true })
    if (typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(this._boundCompute)
      this._resizeObserver.observe(scrollEl)
    }
    this.requestCompute()
  }

  disconnect() {
    if (this._scrollEl) this._scrollEl.removeEventListener("scroll", this._boundCompute)
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver = null
    }
    if (this._raf) cancelAnimationFrame(this._raf)
  }

  requestCompute() {
    if (this._raf) return
    this._raf = requestAnimationFrame(() => {
      this._raf = null
      this.compute()
    })
  }

  compute() {
    if (!this._scrollEl) return
    const t = this.constructor.THRESHOLD_PX
    const offset = this.constructor.ARROW_OFFSET_PX
    const top = this._scrollEl.scrollTop
    const max = this._scrollEl.scrollHeight - this._scrollEl.clientHeight
    const topVisible = top > t
    const bottomVisible = top < max - t
    if (this.hasTopTarget) this.topTarget.classList.toggle("tui-scroll-indicator--visible", topVisible)
    if (this.hasBottomTarget) this.bottomTarget.classList.toggle("tui-scroll-indicator--visible", bottomVisible)
    // Handle position — pixel-based with reserved arrow zones.
    //   - USABLE track height = clientHeight − (offset × 2)
    //   - Handle top = offset + (scrollProgress × usableHeight)
    // This guarantees the █ handle never sits on top of the ▲ ▼ arrows
    // (e.g. scrollTop=0 puts handle at y=offset, NOT y=0 where ▲ lives).
    if (this.hasHandleTarget && max > 0) {
      const clientH = this._scrollEl.clientHeight
      const usableH = Math.max(0, clientH - offset * 2)
      const progress = Math.max(0, Math.min(1, top / max))
      const handleY = offset + progress * usableH
      this.handleTarget.style.top = `${handleY}px`
      this.handleTarget.classList.toggle("tui-scroll-indicator--visible", max > t)
    }
  }
}
