import { Controller } from "@hotwired/stimulus"

/**
 * tui-scroll-indicator — toggles overlay glyphs and positions a
 * floating handle on either the right border (vertical mode, default)
 * or the bottom border (horizontal mode, opt-in) of a scrollable
 * container, based on scroll position.
 *
 * ## Axis modes
 *
 * The controller supports TWO axis modes via the `axis` value
 * (`data-tui-scroll-indicator-axis-value`):
 *
 *   - "vertical" (default) — paired ▲/▼ + █ on the RIGHT border.
 *     Targets: `top`, `bottom`, `handle`. Reads scrollTop /
 *     scrollHeight / clientHeight. Handle position is a Y pixel value
 *     in `style.top`.
 *
 *   - "horizontal" — paired ◀/▶ + ▬ on the BOTTOM border. Targets:
 *     `left`, `right`, `handle`. Reads scrollLeft / scrollWidth /
 *     clientWidth. Handle position is an X pixel value in
 *     `style.left`.
 *
 * Either axis uses the SAME `handle` target — the controller writes
 * `style.top` (vertical) or `style.left` (horizontal) based on the
 * axis value, so the same `<span data-…-target="handle">` element
 * serves both. CSS chooses which axis is rendered via
 * `.tui-scroll-indicator--horizontal` modifier classes; the markup
 * pairs each container's correct target set with its axis (vertical
 * containers emit `top`/`bottom`; horizontal emit `left`/`right`).
 *
 * ## Visibility rules
 *
 * Per-axis (substitute leading/trailing for top/bottom or left/right):
 *
 *   - leading visible  when scrollLeading > THRESHOLD_PX
 *   - trailing visible when scrollLeading + clientLeading
 *                       < scrollExtent - THRESHOLD_PX
 *   - Neither visible when content does not overflow OR scrolled
 *     exactly to the corresponding edge.
 *   - Handle visible whenever content overflows (max > THRESHOLD_PX);
 *     positioned in pixels along the active axis directly. The usable
 *     handle track reserves ARROW_OFFSET_PX at each end so the █ / ▬
 *     handle never overlaps the arrow glyphs.
 *
 * Recomputed on:
 *   - connect (initial paint)
 *   - scroll event (throttled via requestAnimationFrame)
 *   - resize event (via ResizeObserver)
 *
 * ## Scroll target (FB-SCROLL-CLIP 2026-05-24)
 *
 * When a `scroll` target element is present (e.g., the inner
 * `.tui-panel-fieldset__scroll` wrapper that owns `overflow-y: auto`
 * / `overflow-x: auto` while the fieldset itself stays `overflow:
 * visible`), the controller attaches its scroll + resize listeners to
 * that inner element rather than `this.element`. This allows the
 * fieldset to remain `overflow: visible` so the absolutely-positioned
 * indicator glyphs at `right: -7px` / `bottom: -7px` are not clipped
 * by the fieldset's own overflow box. If no `scroll` target is
 * registered, falls back to `this.element` for backwards
 * compatibility with standalone usage.
 *
 * The indicators are pointer-events: none — purely visual hints.
 * Scroll itself is mouse-wheel + keyboard cursor (j/k) handled
 * elsewhere.
 */
export default class extends Controller {
  static targets = ["top", "bottom", "left", "right", "handle", "scroll"]
  static values = { axis: { type: String, default: "vertical" } }
  static THRESHOLD_PX = 2
  // 2026-05-24 — Reserve N px at each end of the scroll track so the
  // handle glyph never overlaps the arrow glyphs. Same offset both
  // ends for visual symmetry.
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
    window.addEventListener("resize", this._boundCompute, { passive: true })
    this.requestCompute()
  }

  disconnect() {
    if (this._scrollEl) this._scrollEl.removeEventListener("scroll", this._boundCompute)
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver = null
    }
    window.removeEventListener("resize", this._boundCompute)
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
    if (this.axisValue === "horizontal") {
      this._computeHorizontal()
    } else {
      this._computeVertical()
    }
  }

  _computeVertical() {
    const t = this.constructor.THRESHOLD_PX
    const offset = this.constructor.ARROW_OFFSET_PX
    const scrollPos = this._scrollEl.scrollTop
    const max = this._scrollEl.scrollHeight - this._scrollEl.clientHeight
    const leadingVisible = scrollPos > t
    const trailingVisible = scrollPos < max - t
    if (this.hasTopTarget) this.topTarget.classList.toggle("tui-scroll-indicator--visible", leadingVisible)
    if (this.hasBottomTarget) this.bottomTarget.classList.toggle("tui-scroll-indicator--visible", trailingVisible)
    if (this.hasHandleTarget) {
      if (max > 0) {
        const clientH = this._scrollEl.clientHeight
        const usableH = Math.max(0, clientH - offset * 2)
        const progress = Math.max(0, Math.min(1, scrollPos / max))
        const handleY = offset + progress * usableH
        this.handleTarget.style.top = `${handleY}px`
      }
      this.handleTarget.classList.toggle("tui-scroll-indicator--visible", max > t)
    }
  }

  _computeHorizontal() {
    const t = this.constructor.THRESHOLD_PX
    const offset = this.constructor.ARROW_OFFSET_PX
    const scrollPos = this._scrollEl.scrollLeft
    const max = this._scrollEl.scrollWidth - this._scrollEl.clientWidth
    const leadingVisible = scrollPos > t
    const trailingVisible = scrollPos < max - t
    if (this.hasLeftTarget) this.leftTarget.classList.toggle("tui-scroll-indicator--visible", leadingVisible)
    if (this.hasRightTarget) this.rightTarget.classList.toggle("tui-scroll-indicator--visible", trailingVisible)
    if (this.hasHandleTarget) {
      if (max > 0) {
        const clientW = this._scrollEl.clientWidth
        const usableW = Math.max(0, clientW - offset * 2)
        const progress = Math.max(0, Math.min(1, scrollPos / max))
        const handleX = offset + progress * usableW
        this.handleTarget.style.left = `${handleX}px`
      }
      this.handleTarget.classList.toggle("tui-scroll-indicator--visible", max > t)
    }
  }
}
