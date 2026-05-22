import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-bottom-status-bar"
//
// 2026-05-22 (Phase 2E) — mode-changed handling moved OUT of this
// controller to the new tui-mode-lozenge delegator + tui-transition
// outlet living on the mode lozenge itself. This controller now exists
// for future BSB-scoped concerns (section highlight on TST nav, hint
// chord state) and stays as the canonical mount point for the footer.
export default class extends Controller {
  connect() {
    // Reserved for BSB-scoped wiring. Mode lozenge is autonomous.
  }

  disconnect() {
    // Reserved.
  }
}
