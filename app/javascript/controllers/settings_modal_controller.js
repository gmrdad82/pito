import { Controller } from "@hotwired/stimulus"

// Phase 29 (settings refactor) — settings security modal.
//
// Mirrors `notification-modal` / `calendar-entry-modal`. The controller
// is mounted once on the layout-positioned `<dialog>` via
// `_settings_modal.html.erb` (rendered from `settings/index`). Row
// links carry `data-action="click->settings-modal#open"` and a `href`
// that doubles as the JS-off fallback URL and the Turbo Frame src.
//
//   1. Prevent default link navigation.
//   2. Optionally set the header title from
//      `data-settings-modal-title-param`.
//   3. Set the `settings_modal_frame` Turbo Frame's `src` to `href` —
//      Turbo fetches the standalone route and swaps the contents in.
//   4. `dialog.showModal()` so the dialog renders on top.
//
// Closing:
//   - Escape key — native <dialog> (suppressed when non-dismissible).
//   - Click outside — `clickOutside` action (suppressed when
//     non-dismissible).
//   - `[ close ]` bracketed link — `data-action="click->settings-modal#close"`
//     (the link is also omitted from the partial when non-dismissible).
//
// Multi-step flows (TOTP enrollment) work because Turbo Frame swaps
// inside the frame on form submits — the dialog stays open across
// navigations within the frame.
//
// Phase 32 (settings refactor polish — Concern 2). Two optional
// values on the controller element:
//   * `auto-open-url` — when set on connect, the controller opens
//     the dialog and points the Turbo Frame at the URL. Used by
//     the mandatory-2FA gate to auto-open the TOTP enrollment view.
//   * `non-dismissible` — "yes" suppresses every dismiss path
//     (Escape, click-outside, close link). The dialog stays open
//     until the page re-renders without the value (e.g. the
//     enrollment confirm response redirects off /settings or the
//     gate releases on the next request).
export default class extends Controller {
  static targets = ["dialog", "frame", "title"]
  static values = {
    autoOpenUrl: { type: String, default: "" },
    nonDismissible: { type: String, default: "no" },
  }

  connect() {
    if (this.autoOpenUrlValue && this.autoOpenUrlValue.length > 0) {
      this._openWithUrl(this.autoOpenUrlValue)
    }
  }

  open(event) {
    if (event) event.preventDefault()
    const anchor = event && event.currentTarget
    const url = (anchor && anchor.getAttribute("href")) || null
    if (!url || url === "#") return

    const title = anchor && anchor.dataset.settingsModalTitleParam
    if (title && this.hasTitleTarget) {
      this.titleTarget.textContent = title
    }

    this._openWithUrl(url)
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.nonDismissibleValue === "yes") return
    this._closeDialog()
  }

  clickOutside(event) {
    if (this.nonDismissibleValue === "yes") return
    if (event.target === this.dialogTarget) {
      this.close(event)
    }
  }

  // Native `<dialog>` emits a `cancel` event when the user hits
  // Escape. preventDefault on the event keeps the dialog open. We
  // use this single hook because the keydown listener route would
  // race against the dialog's built-in handler.
  cancelDismiss(event) {
    if (this.nonDismissibleValue !== "yes") return
    if (event) event.preventDefault()
  }

  _openWithUrl(url) {
    if (this.hasFrameTarget) {
      this.frameTarget.setAttribute("src", url)
    }
    if (this.hasDialogTarget && typeof this.dialogTarget.showModal === "function") {
      if (!this.dialogTarget.open) {
        this.dialogTarget.showModal()
      }
    }
  }

  _closeDialog() {
    if (this.hasDialogTarget && typeof this.dialogTarget.close === "function") {
      this.dialogTarget.close()
    }
    if (this.hasFrameTarget) {
      this.frameTarget.removeAttribute("src")
      this.frameTarget.replaceChildren()
    }
  }
}
