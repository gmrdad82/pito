import { Controller } from "@hotwired/stimulus"

// Phase 15 calendar UX restructure — `/calendar` view-persistence router.
//
// Two responsibilities, gated by which values are wired:
//
// 1. Bootstrap (mounted on `Calendar::RouterController#show`): reads the
//    `pito-calendar-view` localStorage key on `connect()` and
//    `window.location.replace`s to either the schedule or the current
//    month grid. Using `replace` (not `assign`) keeps `/calendar` out of
//    browser history so [back] from the resolved view returns to
//    wherever the user was before. On fresh visits with no preference
//    (or in environments without localStorage), the router page's
//    `<meta http-equiv="refresh">` falls through to the month grid
//    after a 1s delay — JS normally wins this race.
//
// 2. Persist (mounted on the schedule and month views, around the
//    [month]/[schedule] toggle): a `persistMonth` / `persistSchedule`
//    action writes the chosen view to localStorage so the next visit
//    to `/calendar` honors the most-recent toggle. The toggle links
//    target their canonical view URLs directly — they do NOT bounce
//    through `/calendar`, so a stale preference can never swallow the
//    click. Persist is best-effort: a failed write does not block
//    navigation.
//
// `connect()` only redirects when the corresponding value is wired,
// so mounting this controller on a regular calendar view (without
// `month-path-value` / `schedule-path-value`) is a safe no-op.
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
    } else if (preference !== "schedule" && this.monthPathValue) {
      window.location.replace(this.monthPathValue)
    }
  }

  persistMonth() {
    this.#write("month")
  }

  persistSchedule() {
    this.#write("schedule")
  }

  #write(view) {
    try {
      localStorage.setItem("pito-calendar-view", view)
    } catch (_e) {
      // localStorage unavailable — silently skip; navigation still
      // proceeds via the link's href.
    }
  }
}
