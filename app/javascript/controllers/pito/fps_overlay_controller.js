// pito--fps-overlay
//
// F9 toggles the FPS chip (Pito::FpsOverlayComponent's `.pito-fps-overlay`
// wrapper) between hidden and visible. The `#pito-fx-fps` sampler inside is
// itself visibility-gated, so this controller does nothing but flip the
// `hidden` class — an untoggled chip stays inert.
//
// Ctrl+F9 is the shared perf keybind across every PITO surface (pito web,
// pitomd, pito-tui) — deliberately Ctrl-modified and deliberately
// undocumented (owner call, 3.0.x): plain F9 is reserved for the operator's
// own tooling (e.g. a WM-level dictation push-to-talk), so this handler
// must NEVER fire on unmodified F9. Alt+F9 and Meta+F9 stay with the
// OS/window manager.
//
// Document-level delegation (same shape as pito--anchor-jump /
// pito--command-palette): connect() binds to `document`, not `this.element`,
// so F9 works from anywhere on the page, not just while the chip has focus.
//
// Unlike the other global-key handlers here (chat_form_controller,
// share_unfold_controller), this one does NOT fall through when focus is
// inside an input/textarea/contenteditable: F9 is a function key that
// inserts no text, so there's nothing for the chatbox to "own" here — and
// since pito is a chat-first UI whose chatbox effectively always has focus,
// that guard made the toggle unreachable in practice.
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
    // Ctrl+F9 ONLY (see header) — unmodified F9 belongs to the operator's
    // own tooling and must pass through untouched; Alt/Meta combos stay
    // with the OS/window manager.
    if (event.key !== "F9" || !event.ctrlKey) return
    if (event.altKey || event.metaKey) return

    event.preventDefault()
    this.element.classList.toggle("hidden")
  }
}
