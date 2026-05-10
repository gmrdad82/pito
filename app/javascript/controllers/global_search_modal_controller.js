import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish — global search modal.
//
// Dialog rendered once in `app/views/layouts/application.html.erb`
// (`shared/_search_modal`). Opened by the `/` keypress (handled in
// `keyboard_controller.js#focusSearchInput`) — the controller's
// `open` method `showModal()`s the <dialog> and autofocuses the
// input. `Escape` and click-outside close the modal natively.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["input"]

  open(event) {
    if (event) event.preventDefault()
    if (typeof this.element.showModal === "function") {
      this.element.showModal()
    }
    if (this.hasInputTarget) {
      // Defer focus so the dialog's own focus management settles first.
      setTimeout(() => this.inputTarget.focus(), 0)
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
