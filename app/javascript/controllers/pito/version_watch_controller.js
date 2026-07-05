// pito--version-watch
//
// The receiving end of the version heartbeat (G80). VersionHeartbeatJob
// replaces #pito-server-version on pito:global every 5 minutes; each replace
// mounts a fresh copy of this controller, whose value carries the RUNNING
// server build. Compare it against the build this PAGE was rendered by (the
// pito-version meta): a mismatch means the server was updated under the open
// tab — clone the server-rendered refresh nudge into the scrollback.
//
// This heartbeat exists because the one-shot reconnect check (cable-health)
// can miss the update's reconnect churn (1.1.0 shipped and the owner's open
// tab never heard about it): a recurring push reaches every client connected
// at ANY tick, no matter how messy the reconnect was.
//
// The nudge is raised at most once per page life — pito--cable-health and
// this controller share the guard via the template's removal: #showNudge
// consumes the <template> node, so a second caller finds nothing to clone.
//
//   <div id="pito-server-version" class="hidden"
//        data-controller="pito--version-watch"
//        data-pito--version-watch-version-value="1.1.0"></div>

import { Controller } from "@hotwired/stimulus"
import { showRefreshNudge } from "controllers/pito/refresh_nudge_controller"

export default class extends Controller {
  static values = { version: String }

  connect() {
    this.pageVersion = document.querySelector('meta[name="pito-version"]')?.content || null
    this.#updateMiniStatus()
    this.#compare()
  }

  // Covers in-place attribute updates too (defensive — the heartbeat's
  // turbo_stream.replace normally remounts the whole node instead).
  versionValueChanged() {
    this.#updateMiniStatus()
    this.#compare()
  }

  // G87: the mini status' dedicated app-version listener — every heartbeat
  // writes the SERVER's current version into the bar's @suffix slot, so the
  // bar tracks the running app live (the page build stays in the meta; the
  // nudge still announces the skew and owns the reload).
  #updateMiniStatus() {
    if (!this.versionValue) return
    const slot = document.getElementById("pito-mini-status-version")
    if (slot) slot.textContent = `@${this.versionValue}`
  }

  #compare() {
    if (!this.pageVersion || !this.versionValue) return
    if (this.versionValue !== this.pageVersion) showRefreshNudge()
  }
}
