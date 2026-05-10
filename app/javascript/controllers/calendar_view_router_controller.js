import { Controller } from "@hotwired/stimulus"

// Phase 15 calendar UX restructure — `/calendar` view-persistence router.
//
// Mounted on the thin `Calendar::RouterController#show` page. Reads the
// `pito-calendar-view` localStorage key and `replace`s the current URL
// with either the schedule or the current month grid. Using
// `window.location.replace` (not `assign`) keeps `/calendar` out of
// browser history so [back] from the resolved view returns to wherever
// the user was before.
//
// On fresh visits with no preference (or in environments without
// localStorage), the page's `<meta http-equiv="refresh">` falls through
// to the month grid after a 1s delay — JS normally wins this race.
export default class extends Controller {
  static values = {
    monthPath: String,
    schedulePath: String
  }

  connect() {
    let preference = null
    try {
      preference = localStorage.getItem("pito-calendar-view")
    } catch (_e) {
      // localStorage unavailable — fall through to meta-refresh.
    }

    if (preference === "schedule" && this.schedulePathValue) {
      window.location.replace(this.schedulePathValue)
    } else if (this.monthPathValue) {
      window.location.replace(this.monthPathValue)
    }
  }
}
