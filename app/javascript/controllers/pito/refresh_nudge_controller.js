// pito--refresh-nudge
//
// The refresh nudge is TAPPABLE (G73): the Android shell has no keyboard and
// no refresh affordance (pull-to-refresh is deliberately off), so the yellow
// segment itself — yellow being the action class — carries the reload. A
// full location.reload() on purpose: the point of the nudge is fetching the
// NEW build's CSS/JS, which a Turbo visit would not re-fetch.
//
// Mounted on the template's clone by cable-health; Stimulus connects it the
// moment the clone lands in the scrollback DOM.
//
//   <div data-controller="pito--refresh-nudge"
//        data-action="click->pito--refresh-nudge#reload">…</div>

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reload() {
    window.location.reload()
  }
}
