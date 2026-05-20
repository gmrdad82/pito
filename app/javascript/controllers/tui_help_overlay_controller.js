import { Controller } from "@hotwired/stimulus"

// Beta 4 — Phase F1. Stimulus controller for the TUI help overlay
// (`Tui::HelpOverlayComponent`, mounted in
// `app/views/layouts/application.html.erb`). Listens for `?` at
// document level and toggles the `<dialog>` open/closed via the
// browser-native `showModal()` / `close()` API so the overlay lands
// in the top layer (above any pre-existing `<dialog>`).
//
// Gating mirrors the other global keydown controllers
// (`flat_key_controller.js`, `leader_menu_controller.js`):
//   * a form-entry surface (input / textarea / select /
//     [contenteditable]) absorbs the keystroke so typing a `?` into a
//     search field still works.
//   * Ctrl / Meta modifiers bail (Shift is allowed because `?` itself
//     requires Shift on most layouts).
//
// The controller intentionally does NOT consult the
// `pito-keybindings` schema or the `pito-enroll-totp-gate` meta tag.
// The help overlay is a reference surface — showing it during the
// mandatory-2FA enrollment screen is harmless (the user still can't
// navigate anywhere) and arguably useful (they discover `?` exists).
// Each other global controller owns its own gate logic; this one
// stays minimal on purpose.
export default class extends Controller {
  connect() {
    this.boundHandler = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandler)
  }

  handleKey(event) {
    if (event.target.matches("input, textarea, select, [contenteditable]")) return
    if (event.ctrlKey || event.metaKey || event.altKey) return

    if (event.key === "?") {
      this.toggle()
      event.preventDefault()
    } else if (event.key === "Escape" && this.element.open) {
      this.close()
      event.preventDefault()
    }
  }

  toggle() {
    if (this.element.open) this.close()
    else this.open()
  }

  open() {
    this.element.showModal()
  }

  close() {
    this.element.close()
  }
}
