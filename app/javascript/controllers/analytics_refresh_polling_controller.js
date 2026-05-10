import { Controller } from "@hotwired/stimulus"

// Phase 13.3 — Polling fallback for the analytics dashboard. When
// the page renders the `syncing...` flash or a chart-level loading
// caption, the controller polls the page URL every 5 seconds via
// `fetch` + Turbo Drive's morph refresh, so the chart partials pick
// up freshly synced data even if the Turbo Stream broadcast is
// missed.
//
// Master-agent decision 6 keeps both refresh paths: Turbo Streams
// from the sync jobs are the primary, this polling controller is
// defense-in-depth.
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 5000 },
    active: { type: Boolean, default: false }
  }

  connect() {
    if (!this.activeValue) return
    this._scheduleNext()
  }

  disconnect() {
    if (this._timer) {
      clearTimeout(this._timer)
      this._timer = null
    }
  }

  _scheduleNext() {
    this._timer = setTimeout(() => this._refresh(), this.intervalValue)
  }

  _refresh() {
    if (!this.activeValue) return
    if (typeof window.Turbo !== "undefined" && window.Turbo.visit) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    }
    // No re-schedule — Turbo's replace will reconnect this controller.
  }
}
