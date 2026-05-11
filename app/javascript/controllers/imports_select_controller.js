// Phase 22 — Imports::Channels selection Stimulus controller.
//
// Keeps the `[import]` submit button on the channel-pick modal step
// (`/imports/channels`) disabled until the user ticks at least one
// channel checkbox. Re-enables the moment any checkbox is checked;
// re-disables when the last tick is cleared.
//
// The server enforces the same invariant (empty `channel_ids` returns
// 422 / redirects with `select at least one channel`), so this is a
// UX layer on top of a hard server check.
//
// NO window.confirm / alert / data-turbo-confirm anywhere in this
// file (CLAUDE.md hard rule).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "submit"]

  connect() {
    this.refresh()
  }

  refresh() {
    if (!this.hasSubmitTarget) return
    const anyChecked = this.checkboxTargets.some((cb) => cb.checked)
    this.submitTarget.disabled = !anyChecked
  }
}
