// Phase 12 — pre-publish checklist Stimulus controller.
//
// Disables the [ confirm publish ] / [ confirm schedule ] submit
// button until all four checkboxes are checked. The server enforces
// the same invariant as defense-in-depth (the controller's
// validate_publish / validate_schedule helpers reject any false
// boolean), so a user with JS disabled or a misbehaving client
// cannot smuggle a publish past the gate.
//
// NO window.confirm / alert / data-turbo-confirm anywhere in this
// file (CLAUDE.md hard rule).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "submit", "form"]

  connect() {
    this.refresh()
  }

  refresh() {
    if (!this.hasSubmitTarget) return
    const allChecked = this.checkboxTargets.every((cb) => cb.checked)
    this.submitTarget.disabled = !allChecked
  }
}
