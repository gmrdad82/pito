import { Controller } from "@hotwired/stimulus";

// FB-124 (2026-05-21). Canonical confirmation dialog controller.
//
// Wires the universal dismiss behaviour for `Tui::ConfirmationDialogComponent`:
//
//   * `[Esc]` closes the dialog (the only canonical dismiss path).
//   * Backdrop clicks DO NOT dismiss (FB-127 universal rule). The native
//     `<dialog>` element treats a click on the dialog node itself (vs.
//     a click on its children) as a backdrop click; preventing the
//     default on that branch keeps the dialog open.
//   * `open()` / `close()` are exposed for callers that want to drive
//     the dialog from another controller (e.g. the sessions bulk-revoke
//     controller mutates the message + form action before calling
//     `showModal()`).
export default class extends Controller {
  connect() {
    this.boundKeydown = this.handleKeydown.bind(this);
    this.element.addEventListener("keydown", this.boundKeydown);
    this.boundBackdropClick = this.handleBackdropClick.bind(this);
    this.element.addEventListener("click", this.boundBackdropClick);
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.boundKeydown);
    this.element.removeEventListener("click", this.boundBackdropClick);
  }

  open() {
    this.element.showModal();
  }

  close() {
    this.element.close();
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      this.close();
    }
  }

  handleBackdropClick(event) {
    // FB-127: backdrop clicks DO NOT dismiss. The browser fires the
    // click on the <dialog> element itself when the user clicks the
    // backdrop region; clicks on inner children bubble through their
    // own targets first.
    if (event.target === this.element) {
      event.preventDefault();
    }
  }
}
