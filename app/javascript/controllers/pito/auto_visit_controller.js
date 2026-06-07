// Pito::AutoVisitController
//
// After a short delay, removes the pito-shimmer class from the copy target
// and auto-clicks the link (opening the channel's YouTube page in a new tab).
//
// Values:
//   delay   (Number)  — ms before the click fires (default: 1000)
//   linkId  (String)  — id of the anchor to click (fallback when link target
//                       is not directly inside this controller's element)
//
// Targets:
//   copy   — the shimmer span; pito-shimmer is removed after the delay.
//   link   — the hidden anchor to click.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["copy", "link"]
  static values  = { delay: Number, linkId: String }

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
    }, ms)
  }

  disconnect() {
    clearTimeout(this._timer)
  }
}
