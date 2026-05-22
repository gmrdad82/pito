import { Controller } from "@hotwired/stimulus"

// tui-sidekiq-stats — listens for `tui:sidekiq-changed` on document and
// patches the three child cells (busy / enqueued / retry) via their
// colocated `tui-transition` controllers. Reads the cable payload
// `{ busy, enqueued, retry }` and applies short-format + width-lock
// before delegating `setValue(...)` to each cell's transition controller.
//
// Mount: parent `<span class="tui-sidekiq-row sb-sidekiq">`.
// Children: `<span class="tui-sidekiq-cell sb-sk-cell"
//            data-tui-sidekiq-stats-cell-name-value="busy|enqueued|retry"
//            data-controller="tui-transition" ...>`.
//
// The JS short-format MUST match `Pito::Formatter::ShortNumber` exactly:
//
//   0           → "0"
//   32          → "32"
//   999         → "999"
//   1_000       → "1k"
//   22_345      → "22k"
//   899_000     → "899k"
//   1_000_000   → "1M"
//   999_999_999 → "999M"
//   1_000_000_000 → "1B"
//
// @contract see app/services/pito/formatter/short_number.rb
// @contract see app/javascript/controllers/tui_transition_controller.js
export default class extends Controller {
  static CELL_WIDTH = 4

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
    const payload = event?.detail || {}
    this.updateCell("busy", payload.busy)
    this.updateCell("enqueued", payload.enqueued)
    this.updateCell("retry", payload.retry)
  }

  updateCell(name, rawValue) {
    if (typeof rawValue === "undefined") return
    const el = this.element.querySelector(
      `.tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value="${name}"]`
    )
    if (!el) return
    const ctrl = this.application.getControllerForElementAndIdentifier(el, "tui-transition")
    if (!ctrl) return
    ctrl.setValue(this.shortFormatPadded(rawValue))
  }

  shortFormatPadded(n) {
    return this.shortFormat(n).padEnd(this.constructor.CELL_WIDTH, " ")
  }

  shortFormat(n) {
    if (n === null || n === undefined) return ""
    const parsed = parseInt(n, 10)
    if (!Number.isFinite(parsed)) return ""
    const abs = Math.abs(parsed)
    if (abs < 1000) return abs.toString()
    if (abs < 1_000_000) return `${Math.floor(abs / 1000)}k`
    if (abs < 1_000_000_000) return `${Math.floor(abs / 1_000_000)}M`
    return `${Math.floor(abs / 1_000_000_000)}B`
  }
}
