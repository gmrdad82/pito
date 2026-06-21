// Pito::NotificationsCountController
//
// Mounted on the notifications count span inside #pito-mini-status.
// Because broadcast_global_mini_status does a Turbo Stream replace of that
// whole wrapper, every update tears down and rebuilds the span — triggering
// disconnect() then connect() on this controller each time.
//
// Module-level prevCount survives across replacements, so we can compare
// the incoming count to the one from the previous render and dispatch
// pito:notification-arrived when the unread count increases (new notif).
// A decrease (mark-as-read) or no change must NOT dispatch the event.

import { Controller } from "@hotwired/stimulus"

// Intentionally module-scoped: survives Turbo Stream element replacements.
let prevCount = null

export default class extends Controller {
  static values = { count: Number }

  connect() {
    const count = this.countValue

    if (prevCount !== null && count > prevCount) {
      document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    }

    prevCount = count
  }

  // prevCount is intentionally NOT reset on disconnect so it persists
  // across the Turbo Stream replacement cycle.
}
