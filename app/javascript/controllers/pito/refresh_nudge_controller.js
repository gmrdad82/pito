// pito--refresh-nudge
//
// The refresh nudge is TAPPABLE: the Android shell has no keyboard and
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

// Clone the layout's server-rendered nudge template into the scrollback —
// shared by pito--cable-health (reconnect check) and pito--version-watch
// (the 5-min heartbeat). CONSUMES the template node, which doubles as
// the once-per-page-life guard: whichever caller fires second finds nothing
// to clone. Returns true when the nudge landed.
export function showRefreshNudge() {
  const template   = document.getElementById("pito-refresh-nudge")
  const scrollback = document.getElementById("pito-scrollback")
  if (!template || !scrollback) return false

  scrollback.appendChild(template.content.cloneNode(true))
  template.remove()
  scrollback.lastElementChild?.scrollIntoView({ block: "end" })
  return true
}

export default class extends Controller {
  reload() {
    window.location.reload()
  }
}
