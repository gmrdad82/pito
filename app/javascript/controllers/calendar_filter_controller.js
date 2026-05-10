import { Controller } from "@hotwired/stimulus"

// Phase 15 §2 + calendar UX restructure — calendar filter cluster
// controller.
//
// Filter state itself is URL-driven (server-rendered hrefs encode the
// next state); the Stimulus controller is a hook for:
//
//   1. Persisting the active calendar view (`pito-calendar-view`)
//      so the `/calendar` router lands the user on the same view next
//      visit. Configured via `data-calendar-filter-view-value="…"` —
//      `"month"` on the month grid, `"schedule"` on the schedule.
//   2. Future keyboard shortcuts / multi-select enhancements.
//
// `masterToggle` and `kindToggle` targets are declared so future
// JS-side enhancements (e.g. shift-click select-all) can find the
// chips without DOM crawling. v1 leaves them unbound.
export default class extends Controller {
  static targets = [ "masterToggle", "kindToggle" ]
  static values = {
    view: String
  }

  connect() {
    if (this.hasViewValue && this.viewValue) {
      try {
        localStorage.setItem("pito-calendar-view", this.viewValue)
      } catch (_e) {
        // localStorage unavailable — persistence is best-effort.
      }
    }
  }
}
