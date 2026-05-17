import { Controller } from "@hotwired/stimulus"

// Calendar month-view router signal.
//
// 2026-05-17 — the global `[` / `]` / `t` keybinds that paged the
// calendar month grid were removed in the legacy-keyboard-shortcut
// sweep. Per the user rule the only allowed global keybindings are
// the leader-menu (SPACE → driven by `config/keybindings.yml`
// `menus:`) and per-page actions (`page_actions:` in the same file);
// `[` and `]` were in neither. Calendar prev/next/today now flow
// exclusively through the bracketed-link affordances in the month
// header (`_navigation.html.erb`) and via the leader-menu's
// `calendar` submenu (SPACE → c → s/m/t → schedule/month/today).
//
// What remains: on connect the controller writes
// `pito-calendar-view = "month"` so the `/calendar` router page
// (calendar-view-router) lands the user back on the month grid by
// default on a future visit. The schedule controller has its own
// writer.
export default class extends Controller {
  static values = {
    persistView: { type: String, default: "month" }
  }

  connect() {
    try {
      if (this.persistViewValue) {
        localStorage.setItem("pito-calendar-view", this.persistViewValue)
      }
    } catch (_e) {
      // localStorage unavailable (private mode quota / disabled).
      // Persistence is best-effort; the URL remains the canonical
      // source of truth.
    }
  }
}
