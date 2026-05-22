import { Controller } from "@hotwired/stimulus"

/**
 * tui-date-time — thin delegator (Phase 2C, 2026-05-22).
 *
 * Owns:
 *   - 1Hz local tick that pushes the new formatted time into the
 *     colocated `tui-transition` outlet via `setValue(...)`. The
 *     diff-only scramble in `tui-transition` means only the chars that
 *     changed animate — the static colons and unchanged digits stay put.
 *   - `tui:notifications-changed` document-event listener that flips
 *     the outlet's color between "muted" (default) and "accent" (when
 *     `event.detail.future_count > 0`).
 *
 * Format shape MUST mirror `Tui::DateTimeComponent.format(time)` in
 * Ruby — otherwise the very first tick after SSR would diff every char
 * and the whole string would scramble. Format: `mon may 22 12:34:56`.
 *
 * Lifecycle:
 *   connect()    — register listener, schedule 1Hz tick
 *   tick()       — push current value into outlet
 *   disconnect() — drop listener + clear interval
 *
 * Outlets:
 *   tui-transition — the colocated canonical animator on the same span.
 */
export default class extends Controller {
  static outlets = ["tui-transition"]
  static WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
  static MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

  connect() {
    this._boundNotif = this.onNotificationsChanged.bind(this)
    document.addEventListener("tui:notifications-changed", this._boundNotif)
    this._tickHandle = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    document.removeEventListener("tui:notifications-changed", this._boundNotif)
    if (this._tickHandle) {
      clearInterval(this._tickHandle)
      this._tickHandle = null
    }
  }

  tick() {
    if (!this.hasTuiTransitionOutlet) return
    this.tuiTransitionOutlet.setValue(this.formatNow())
  }

  onNotificationsChanged(event) {
    if (!this.hasTuiTransitionOutlet) return
    const raw = event?.detail?.future_count
    const count = Number.parseInt(raw || 0, 10)
    this.tuiTransitionOutlet.setColor(Number.isFinite(count) && count > 0 ? "accent" : "muted")
  }

  formatNow() {
    const now = new Date()
    const ctor = this.constructor
    const wd = ctor.WEEKDAYS[now.getDay()]
    const mo = ctor.MONTHS[now.getMonth()]
    const day = now.getDate()
    const pad = (n) => String(n).padStart(2, "0")
    return `${wd} ${mo} ${day} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`
  }
}
