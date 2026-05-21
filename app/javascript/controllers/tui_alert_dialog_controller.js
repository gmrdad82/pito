import { Controller } from "@hotwired/stimulus"

// FB-172 (2026-05-21) — minimal open/close API for `.tui-alert-dialog`.
//
// The dialog frame chrome (backdrop-click-prevent, Esc-only dismissal) is
// handled by the sibling `tui-dialog-frame` controller. This controller
// only exposes imperative `open()` / `close()` so callers (e.g. the
// `keyboard-only` controller in FB-172) can spawn the dialog from JS in
// response to forbidden mouse activity.
export default class extends Controller {
  open() {
    if (!this.element.open) {
      this.element.showModal()
    }
  }

  close() {
    if (this.element.open) {
      this.element.close()
    }
  }
}
