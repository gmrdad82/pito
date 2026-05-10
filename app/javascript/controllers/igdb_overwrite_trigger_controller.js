import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish — overwrite-confirmation trigger.
//
// Attach to any link / button that should open the shared
// `#igdb-overwrite-modal` dialog and target a specific resync URL.
// Usage:
//   data-controller="igdb-overwrite-trigger"
//   data-igdb-overwrite-trigger-path-value="/games/42/resync"
//   data-action="click->igdb-overwrite-trigger#open"
//
// On click, the controller looks up the layout-level dialog by id
// (`igdb-overwrite-modal`), reads its
// `igdb-overwrite-confirm` Stimulus controller instance, sets the
// form action to `pathValue`, and shows the dialog. We avoid
// driving the form action via inline DOM manipulation so the
// confirm controller stays the single source of truth.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static values = { path: String }

  open(event) {
    if (event) event.preventDefault()
    const dialog = document.getElementById("igdb-overwrite-modal")
    if (!dialog) return

    // Resolve the dialog's own controller instance via Stimulus's
    // registered application (mounted at `window.Stimulus` by
    // `controllers/application.js`). If the application isn't
    // available for any reason, fall back to direct showModal().
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(dialog, "igdb-overwrite-confirm")
      if (ctrl && typeof ctrl.setActionAndOpen === "function") {
        ctrl.setActionAndOpen(this.pathValue)
        return
      }
    }

    // Fallback: set the form action manually and open.
    const form = dialog.querySelector("form")
    if (form && this.pathValue) form.action = this.pathValue
    if (typeof dialog.showModal === "function") dialog.showModal()
  }
}
