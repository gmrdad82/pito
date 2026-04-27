import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart"]

  toggle(event) {
    const checkbox = event.target
    const chartDiv = checkbox.closest("[data-chart-sync-target='chart']")
    if (!chartDiv) return

    if (checkbox.checked) {
      chartDiv.dataset.syncGroup = "dashboard"
    } else {
      delete chartDiv.dataset.syncGroup
    }
  }
}
