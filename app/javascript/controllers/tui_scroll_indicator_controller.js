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
 *     positioned via --handle-pct CSS variable (percent of scroll progress).
 *
 * Recomputed on:
 *   - connect (initial paint)
 *   - scroll event (throttled via requestAnimationFrame)
 *   - resize event (via ResizeObserver)
 *
 * The indicators are pointer-events: none — purely visual hints. Scroll
 * itself is mouse-wheel + keyboard cursor (j/k) handled elsewhere.
 */
export default class extends Controller {
  static targets = ["top", "bottom", "handle"]
  static THRESHOLD_PX = 2

  connect() {
    this._boundCompute = this.requestCompute.bind(this)
    this._boundResize = this.requestCompute.bind(this)
    this._raf = null
    this.element.addEventListener("scroll", this._boundCompute, { passive: true })
    if (typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(this._boundResize)
      this._resizeObserver.observe(this.element)
    }
    this.requestCompute()
  }

  disconnect() {
    this.element.removeEventListener("scroll", this._boundCompute)
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
    const t = this.constructor.THRESHOLD_PX
    const top = this.element.scrollTop
    const max = this.element.scrollHeight - this.element.clientHeight
    const topVisible = top > t
    const bottomVisible = top < max - t
    if (this.hasTopTarget) this.topTarget.classList.toggle("tui-scroll-indicator--visible", topVisible)
    if (this.hasBottomTarget) this.bottomTarget.classList.toggle("tui-scroll-indicator--visible", bottomVisible)
    // Handle position: percent of scroll progress, clamped to [0, 100]
    if (this.hasHandleTarget && max > 0) {
      const pct = Math.max(0, Math.min(100, (top / max) * 100))
      this.handleTarget.style.setProperty("--handle-pct", `${pct}%`)
      this.handleTarget.classList.toggle("tui-scroll-indicator--visible", max > t)
    }
  }
}
