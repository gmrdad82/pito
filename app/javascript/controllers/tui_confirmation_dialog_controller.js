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
    this.boundSubmitEnd = this.handleSubmitEnd.bind(this);
    this.element.addEventListener("turbo:submit-end", this.boundSubmitEnd);
    // ADR 0018 — listen for the action-bus confirmation request. The
    // `window.Pito.dispatchAction(name)` flow fires this custom event
    // when the action carries `confirmation:`. If the event's
    // `action.cable_panel` matches this dialog's brand suffix, the
    // dialog re-targets its form action to the event's `path` and
    // opens. Other dialog instances ignore the event.
    this.boundConfirmRequested = this.handleConfirmRequested.bind(this);
    document.addEventListener("pito:action:confirm-requested", this.boundConfirmRequested);
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.boundKeydown);
    this.element.removeEventListener("click", this.boundBackdropClick);
    this.element.removeEventListener("turbo:submit-end", this.boundSubmitEnd);
    document.removeEventListener("pito:action:confirm-requested", this.boundConfirmRequested);
  }

  // The dialog id encodes the brand (e.g. `reindex_meilisearch_confirmation`).
  // Match by comparing the event detail's action name suffix against
  // the dialog id prefix. The first matching dialog (there should be
  // exactly one per action) re-targets its form and opens.
  handleConfirmRequested(event) {
    const action = event.detail;
    if (!action || !action.name) return;
    const expectedId = `${action.name}_confirmation`;
    if (this.element.id !== expectedId) return;
    const form = this.element.querySelector("form");
    if (form && action.path) {
      form.action = action.path;
    }
    this.open();
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

  handleSubmitEnd(event) {
    // Close the dialog after a successful submit so the user is not
    // stranded looking at the open dialog after the action ran. On
    // failure (non-2xx/3xx), leave the dialog open so the user can
    // read any error and retry.
    //
    // FB-149 (2026-05-21). 409 Conflict is treated as a benign
    // no-op — the reindex lock is held and the cable already shows
    // the running state. Close silently instead of letting Turbo
    // render the empty 409 body / navigate to the action URL.
    const statusCode = event.detail?.fetchResponse?.response?.status;
    if (event.detail?.success || statusCode === 409) {
      this.close();
    }
  }
}
