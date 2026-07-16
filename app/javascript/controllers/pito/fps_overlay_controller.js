// pito--fps-overlay
//
// F9 toggles the FPS chip (Pito::FpsOverlayComponent's `.pito-fps-overlay`
// wrapper) between hidden and visible. The `#pito-fx-fps` sampler inside is
// itself visibility-gated, so this controller does nothing but flip the
// `hidden` class — an untoggled chip stays inert.
//
// F9 is the shared perf keybind across every PITO surface (pito web,
// pitomd, pito-tui) — chosen because no browser or terminal binds it by
// default, so it never collides with a built-in shortcut.
//
// Document-level delegation (same shape as pito--anchor-jump /
// pito--command-palette): connect() binds to `document`, not `this.element`,
// so F9 works from anywhere on the page, not just while the chip has focus.
// Guarded like the other global-key handlers here (chat_form_controller,
// share_unfold_controller): a keydown landing in an input/textarea/
// contenteditable falls through untouched — the chatbox owns typing.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onKeydown = this.#toggle.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  #toggle(event) {
    if (event.key !== "F9") return

    const ae = document.activeElement
    const editable = ae && (ae.tagName === "INPUT" || ae.tagName === "TEXTAREA" || ae.isContentEditable)
    if (editable) return

    event.preventDefault()
    this.element.classList.toggle("hidden")
  }
}
