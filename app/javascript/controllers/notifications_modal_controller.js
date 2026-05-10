import { Controller } from "@hotwired/stimulus"

// Layout-level notifications modal.
//
// The Stimulus controller is mounted on `<body>` (alongside `keyboard`)
// so the navbar `[notifications]` link can declare
// `data-action="click->notifications-modal#open"` without having to
// share an ancestor with the dialog's mount. The controller resolves
// the dialog and its Turbo Frame by element id, mirroring how
// `keyboard_controller#openLayoutDialog` resolves the global search
// modals.
//
// `open`:
//   1. `event.preventDefault()` so the `[notifications]` href fallback
//      (full-page /notifications) is suppressed when JS is present.
//   2. Set the frame's `src` to `/notifications?modal=yes`. Turbo fetches
//      that URL and swaps the matching `<turbo-frame>` from the
//      response into the dialog. `modal=yes` follows the project's
//      yes/no boundary convention (CLAUDE.md hard rule).
//   3. `dialog.showModal()`.
//
// `close`:
//   - Closes the dialog AND clears the frame `src`, so the next open
//     re-fetches a fresh list (unread state may have changed).
//
// `clickOutside` and `keydown` mirror the search-modal pattern.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static values = {
    indexUrl: { type: String, default: "/notifications" },
    dialogId: { type: String, default: "notifications-modal" },
    frameId:  { type: String, default: "notifications_modal_frame" },
  }

  open(event) {
    if (event) event.preventDefault()

    const dialog = this._dialog()
    const frame  = this._frame()
    if (!dialog || !frame) return

    const url = new URL(this.indexUrlValue, window.location.origin)
    url.searchParams.set("modal", "yes")
    frame.setAttribute("src", url.toString())

    if (typeof dialog.showModal === "function" && !dialog.open) {
      dialog.showModal()
    }
  }

  close(event) {
    if (event) event.preventDefault()

    const dialog = this._dialog()
    if (dialog && typeof dialog.close === "function" && dialog.open) {
      dialog.close()
    }

    const frame = this._frame()
    if (frame) {
      frame.removeAttribute("src")
      frame.replaceChildren()
    }
  }

  clickOutside(event) {
    const dialog = this._dialog()
    if (dialog && event.target === dialog) {
      this.close(event)
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close(event)
    }
  }

  _dialog() {
    return document.getElementById(this.dialogIdValue)
  }

  _frame() {
    return document.getElementById(this.frameIdValue)
  }
}
