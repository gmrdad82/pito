import { Controller } from "@hotwired/stimulus"

// Universal behavior for `.tui-dialog-frame` dialogs (FB-127 lock 2026-05-21):
//
//   - Backdrop clicks DO NOT dismiss the dialog. The only canonical dismissal
//     path is `[Esc]` (per the `[Esc] to close` hint sitting in the top-right
//     of every `.tui-dialog-frame`). This brings web parity with the TUI client
//     where Esc is the single dismissal grammar.
//
//   - Esc still dismisses natively via the `<dialog>` element's built-in
//     handler. Each consumer that has its own `keydown`/`close` wiring keeps
//     it; this controller does not interfere with those paths.
//
// Mounted by adding `tui-dialog-frame` to a dialog's `data-controller` list.
// Composes cleanly with sibling controllers (e.g. `confirm-modal`,
// `webhook-help-modal`, `tui-help-overlay`) because Stimulus runs each
// controller independently. The intercept happens at the capture phase so it
// fires before the sibling controllers' `clickOutside` actions and stops the
// event from reaching them.
export default class extends Controller {
  connect() {
    this.boundClickGuard = this.handleClick.bind(this)
    // Capture phase: run before bubbling-phase action listeners (e.g.
    // `confirm-modal#clickOutside`, `webhook-help-modal#clickOutside`).
    this.element.addEventListener("click", this.boundClickGuard, true)
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundClickGuard, true)
  }

  handleClick(event) {
    // event.target === this.element means the click landed on the <dialog>
    // element itself (the padding area inside the dialog box bounds, or the
    // backdrop pseudo-element). When the click is on inner content,
    // event.target is a descendant and we let it pass through untouched.
    if (event.target === this.element) {
      event.preventDefault()
      event.stopPropagation()
    }
  }
}
