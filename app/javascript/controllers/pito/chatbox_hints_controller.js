// pito--chatbox-hints
//
// Toggles the two hint filter-row spans inside #pito-chatbox:
//
//   suggestHint  visible  ⟺  a suggestion/hint is active (ghost OR palette)
//                            Driven by document event pito:suggest { detail: { active: bool } }
//                            dispatched by autosuggest_controller.js.
//
//   chatHint     visible  ⟺  the chatbox is NOT focused
//                            Driven by document event pito:focus { detail: { focused: bool } }
//                            dispatched by terminal_caret_controller.js.
//
// Visibility is toggled via classList.toggle("hidden", !visible).
//
// DOM Contract (set by chatbox ERB):
//   Controller:  pito--chatbox-hints  on  #pito-chatbox
//   Target:  <span data-pito--chatbox-hints-target="suggestHint" class="hidden">
//   Target:  <span data-pito--chatbox-hints-target="chatHint"    class="hidden">

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["suggestHint", "chatHint"]

  connect() {
    // Initial state
    this._suggestActive = false
    // Compute initial focused state: focused iff document.activeElement is inside #pito-chatbox.
    this._focused = !!(document.activeElement?.closest?.("#pito-chatbox"))

    // Bind event handlers and store refs for cleanup in disconnect()
    this._onSuggest = (e) => {
      this._suggestActive = !!(e.detail && e.detail.active)
      this._apply()
    }
    this._onFocus = (e) => {
      this._focused = !!(e.detail && e.detail.focused)
      this._apply()
    }

    document.addEventListener("pito:suggest", this._onSuggest)
    document.addEventListener("pito:focus",   this._onFocus)

    // Apply initial visibility immediately
    this._apply()
  }

  disconnect() {
    document.removeEventListener("pito:suggest", this._onSuggest)
    document.removeEventListener("pito:focus",   this._onFocus)
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  _apply() {
    if (this.hasSuggestHintTarget) {
      this.suggestHintTarget.classList.toggle("hidden", !this._suggestActive)
    }
    if (this.hasChatHintTarget) {
      this.chatHintTarget.classList.toggle("hidden", !!this._focused)
    }
  }
}
