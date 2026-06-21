// Pito::NotificationsCountController
//
// Mounted on the notifications count span inside #pito-mini-status.
// Because broadcast_global_mini_status does a Turbo Stream replace of that
// whole wrapper, every update tears down and rebuilds the span — triggering
// disconnect() then connect() on this controller each time.
//
// Module-level prevLatestId survives across replacements, so we compare the
// incoming MAX notification id to the previous render's and dispatch
// pito:notification-arrived only when it RISES (a genuinely new notification).
// A read/unread TOGGLE bumps the unread COUNT but NOT the max id, so it must
// NOT play the chime — that was the annoying false trigger.

import { Controller } from "@hotwired/stimulus"

// Intentionally module-scoped: survives Turbo Stream element replacements.
let prevLatestId = null

export default class extends Controller {
  static values = { count: Number, latestId: Number }

  connect() {
    const latestId = this.latestIdValue

    if (prevLatestId !== null && latestId > prevLatestId) {
      document.dispatchEvent(new CustomEvent("pito:notification-arrived"))
    }

    prevLatestId = latestId
  }

  // prevLatestId is intentionally NOT reset on disconnect so it persists
  // across the Turbo Stream replacement cycle.
}
