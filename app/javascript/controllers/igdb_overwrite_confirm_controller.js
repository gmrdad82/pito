import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish — overwrite-confirmation modal.
//
// Dialog rendered once in `app/views/layouts/application.html.erb`
// (`shared/_igdb_overwrite_modal`). The dialog's <form> action is
// set per-trigger via the sibling `igdb-overwrite-trigger`
// controller, so the same dialog body serves every game id /
// resync route. This controller owns close + click-outside +
// Escape behavior.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["form"]

  setActionAndOpen(path) {
    if (typeof path === "string" && path.length > 0 && this.hasFormTarget) {
      this.formTarget.action = path
    }
    if (typeof this.element.showModal === "function") {
      this.element.showModal()
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (typeof this.element.close === "function" && this.element.open) {
      this.element.close()
    }
  }

  clickOutside(event) {
    if (event.target === this.element) {
      this.element.close()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      if (this.element.open) this.element.close()
    }
  }
}
