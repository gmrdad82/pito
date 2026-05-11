import { Controller } from "@hotwired/stimulus"

// 2026-05-11 — Per-form TOTP-required submit interceptor.
//
// Mounted on each settings form that the fresh-TOTP gate guards
// (YouTube, Voyage.ai, Discord, Slack panes). When `Current.user`
// has 2FA on, the ERB partial sets:
//
//   <form data-controller="totp-modal"
//         data-action="submit->totp-modal#maybeIntercept"
//         data-totp-modal-required-value="yes"> ... </form>
//
// On the FIRST submit, this controller:
//   1. Reads `requiredValue`. When "no" (no 2FA on the user), the
//      submit passes through untouched.
//   2. When "yes", `event.preventDefault()`'s the native submit and
//      tells the layout-level `totp-modal-dialog` controller to
//      `prepare(this.element)`. That controller opens the modal,
//      collects 6 digits, injects a `totp_code` hidden input into
//      THIS form, and re-submits.
//   3. The re-submit carries `data-totp-modal-verified-value="yes"`
//      on the form, which short-circuits this interceptor so the
//      submit flows through to the server.
//
// Failure path: if the server rejects the code (`RecentTotpVerification`
// generic-flash response), the page re-renders with the same form;
// the `verifiedValue` reset happens automatically because the
// Stimulus controller re-mounts on the fresh DOM and reads the
// data-attribute, which the server doesn't set.
export default class extends Controller {
  static values = {
    required: { type: String, default: "no" },
    verified: { type: String, default: "no" },
    dialogId: { type: String, default: "totp-verification-modal" },
  }

  maybeIntercept(event) {
    // Already verified in this round — let the form submit through.
    if (this.verifiedValue === "yes") return

    // Gate dormant — no 2FA on the user. The ERB partial passes "no"
    // so this branch covers the JS-on / 2FA-off case identically to
    // the JS-off case.
    if (this.requiredValue !== "yes") return

    event.preventDefault()

    const dialog = document.getElementById(this.dialogIdValue)
    if (!dialog) {
      // Defensive — if the layout partial wasn't rendered for some
      // reason, fall back to letting the form submit. The server
      // will reject with the same generic-flash copy.
      this.verifiedValue = "yes"
      this.element.submit()
      return
    }

    // Find the dialog's Stimulus controller via the Stimulus application
    // instance. Stimulus exposes `Application#getControllerForElementAndIdentifier`
    // for exactly this kind of cross-controller handshake.
    const app = this.application
    const dialogController = app.getControllerForElementAndIdentifier(
      dialog, "totp-modal-dialog"
    )

    if (dialogController && typeof dialogController.prepare === "function") {
      dialogController.prepare(this.element)
    } else if (typeof dialog.showModal === "function") {
      // Fallback — dialog controller not yet connected. Open the
      // dialog directly; the user can still confirm and the dialog
      // controller will pick up `this._pendingForm` once it connects.
      dialog.showModal()
    }
  }
}
