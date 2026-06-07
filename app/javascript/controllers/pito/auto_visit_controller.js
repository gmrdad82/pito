// Pito::AutoVisitController
//
// After a short delay, removes the pito-shimmer class from the copy target,
// auto-clicks the link ONCE (opening the channel's YouTube page in a new tab),
// then POSTs to the consume endpoint so the source event is persisted in its
// :visited state. Because the persisted :visited body no longer mounts this
// controller, the link is never auto-clicked again on a page refresh.
//
// Values:
//   delay       (Number) — ms before the click fires (default: 1000)
//   linkId      (String) — id of the anchor to click (fallback when link target
//                          is not directly inside this controller's element)
//   consumeUrl  (String) — endpoint to POST { event_id } to after the click.
//
// Targets:
//   copy   — the shimmer span; pito-shimmer is removed after the delay.
//   link   — the hidden anchor to click.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["copy", "link"]
  static values  = { delay: Number, linkId: String, consumeUrl: String }

  connect() {
    const ms = this.delayValue || 1000
    this._timer = setTimeout(() => {
      if (this.hasCopyTarget) {
        this.copyTarget.classList.remove("pito-shimmer")
      }
      const anchor = this.hasLinkTarget
        ? this.linkTarget
        : document.getElementById(this.linkIdValue)
      anchor?.click()
      this._consume()
    }, ms)
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  // Persist the consumed state so a refresh renders the :visited message and
  // never re-clicks. Best-effort: failures are swallowed (worst case is the
  // message re-clicks on the next load, the pre-consume behavior).
  _consume() {
    if (!this.consumeUrlValue) return
    const wrapper = this.element.closest('[id^="event_"]')
    const eventId = wrapper && wrapper.id.replace(/^event_/, "")
    if (!eventId) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.consumeUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        ...(csrf ? { "X-CSRF-Token": csrf } : {}),
      },
      body: JSON.stringify({ event_id: eventId }),
    }).catch(() => {})
  }
}
