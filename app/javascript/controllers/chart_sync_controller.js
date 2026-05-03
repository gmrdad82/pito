import { Controller } from "@hotwired/stimulus"

// Persists which dashboard charts have crosshair sync enabled across browser
// sessions. Each sync-capable chart container has a `[ ] sync` design-system
// bracketed checkbox (CheckboxComponent → md-check) wired as a `checkbox`
// target. The chart container is wired as a `chart` target.
//
// On connect: reads localStorage["pito_dashboard_charts_synced"] (a JSON array
// of chart-id slugs that are currently synced). On first visit (key absent),
// seeds it with the full set of sync-capable chart-ids so every sync checkbox
// starts checked. Subsequent visits restore the user's last toggle state.
//
// State is applied to two surfaces:
//   - the hidden native `<input type="checkbox">` inside CheckboxComponent
//     (its `checked` property drives the `[ ]` / `[x]` indicator via CSS).
//   - the chart container's `data-sync-group` attribute. The crosshair plugin
//     in app/javascript/application.js reads this to decide which charts
//     share hover state. `data-sync-group="dashboard"` opts the chart in;
//     missing attribute opts it out.
export default class extends Controller {
  static targets = ["chart", "checkbox"]

  static STORAGE_KEY = "pito_dashboard_charts_synced"

  connect() {
    let syncedIds = this._readStorage()
    if (syncedIds === null) {
      syncedIds = this._allChartIds()
      this._writeStorage(syncedIds)
    }
    this._applyState(new Set(syncedIds))
  }

  toggle(event) {
    const checkbox = event.currentTarget
    const chartId = checkbox.dataset.chartId
    if (!chartId) return

    const syncedSet = new Set(this._readStorage() || this._allChartIds())
    if (checkbox.checked) {
      syncedSet.add(chartId)
    } else {
      syncedSet.delete(chartId)
    }
    this._writeStorage(Array.from(syncedSet))
    this._applyState(syncedSet)
  }

  _allChartIds() {
    return this.chartTargets.map(el => el.dataset.chartId).filter(Boolean)
  }

  _applyState(syncedSet) {
    this.chartTargets.forEach(chart => {
      const id = chart.dataset.chartId
      const isSynced = syncedSet.has(id)
      if (isSynced) {
        chart.dataset.syncGroup = "dashboard"
      } else {
        delete chart.dataset.syncGroup
      }
    })
    this.checkboxTargets.forEach(cb => {
      const id = cb.dataset.chartId
      cb.checked = syncedSet.has(id)
    })
  }

  _readStorage() {
    try {
      const raw = window.localStorage.getItem(this.constructor.STORAGE_KEY)
      if (raw === null) return null
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : null
    } catch (_e) {
      return null
    }
  }

  _writeStorage(ids) {
    try {
      window.localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify(ids))
    } catch (_e) {
      // localStorage may be disabled (private mode) — silently no-op
    }
  }
}
