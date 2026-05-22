import { Controller } from "@hotwired/stimulus"

/**
 * tui-sidekiq-stats — listens for tui:sidekiq-changed on document and
 * updates the colocated tui-transition outlet with the formatted
 * single-string value + per-segment colors.
 *
 * Format: "b<short(busy)> e<short(enqueued)> r<short(retry)>"
 *
 * Segments JSON (consumed by tui-transition's segmentsValue):
 *   [{ name: "busy",     range: [start, endExclusive], active: busy > 0 },
 *    { name: "enqueued", range: [start, endExclusive], active: enqueued > 0 },
 *    { name: "retry",    range: [start, endExclusive], active: retry > 0 }]
 *
 * Cascade behavior: length changes in any segment ripple-scramble
 * downstream segments via tui-transition's diff-only animateDiff path.
 *
 * Mount: parent `<span class="tui-sidekiq-stats">` with both
 *   `tui-sidekiq-stats` and `tui-transition` Stimulus controllers, plus
 *   `data-tui-sidekiq-stats-tui-transition-outlet=".tui-sidekiq-stats"`.
 *
 * The JS short-format MUST match `Pito::Formatter::ShortNumber` exactly:
 *
 *   0           → "0"
 *   32          → "32"
 *   999         → "999"
 *   1_000       → "1k"
 *   22_345      → "22k"
 *   899_000     → "899k"
 *   1_000_000   → "1M"
 *   999_999_999 → "999M"
 *   1_000_000_000 → "1B"
 *
 * @contract see app/services/pito/formatter/short_number.rb
 * @contract see app/javascript/controllers/tui_transition_controller.js
 */
export default class extends Controller {
  static outlets = ["tui-transition"]

  connect() {
    this._boundChanged = this.onSidekiqChanged.bind(this)
    document.addEventListener("tui:sidekiq-changed", this._boundChanged)
  }

  disconnect() {
    if (this._boundChanged) {
      document.removeEventListener("tui:sidekiq-changed", this._boundChanged)
      this._boundChanged = null
    }
  }

  onSidekiqChanged(event) {
    if (!this.hasTuiTransitionOutlet) return
    const detail = event?.detail || {}
    const busy     = detail.busy ?? 0
    const enqueued = detail.enqueued ?? 0
    const retry    = detail.retry ?? 0

    const bs = "b" + this.shortFormat(busy)
    const es = "e" + this.shortFormat(enqueued)
    const rs = "r" + this.shortFormat(retry)
    const value = `${bs} ${es} ${rs}`

    const bStart = 0
    const bEnd   = bs.length
    const eStart = bEnd + 1
    const eEnd   = eStart + es.length
    const rStart = eEnd + 1
    const rEnd   = rStart + rs.length

    const segments = [
      { name: "busy",     range: [bStart, bEnd], active: this.toInt(busy) > 0 },
      { name: "enqueued", range: [eStart, eEnd], active: this.toInt(enqueued) > 0 },
      { name: "retry",    range: [rStart, rEnd], active: this.toInt(retry) > 0 }
    ]

    // Push the segments descriptor first so tui-transition's
    // segmentsValueChanged callback owns the post-render class flip; then
    // push the value (which triggers animateDiff). The diff replay also
    // calls applySegments() so the new colors land on the new cells.
    this.tuiTransitionOutlet.element.setAttribute(
      "data-tui-transition-segments-value",
      JSON.stringify(segments)
    )
    this.tuiTransitionOutlet.setValue(value)
  }

  toInt(n) {
    const parsed = parseInt(n, 10)
    return Number.isFinite(parsed) ? parsed : 0
  }

  shortFormat(n) {
    if (n === null || n === undefined) return ""
    const parsed = parseInt(n, 10)
    if (!Number.isFinite(parsed)) return ""
    const abs = Math.abs(parsed)
    if (abs < 1000)          return abs.toString()
    if (abs < 1_000_000)     return `${Math.floor(abs / 1000)}k`
    if (abs < 1_000_000_000) return `${Math.floor(abs / 1_000_000)}M`
    return `${Math.floor(abs / 1_000_000_000)}B`
  }
}
