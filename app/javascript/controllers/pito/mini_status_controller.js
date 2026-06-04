// pito--mini-status
//
// Tracks two dynamic states and toggles hint visibility:
//
//   focused      — is the chatbox textarea currently focused?
//   suggestActive — has autosuggest dispatched pito:suggest with active:true?
//
// Toggle rules:
//   suggestHint visible  ⟺  focused && suggestActive
//   chatHint    visible  ⟺  !focused
//
// Both hints are wrapped together with their leading separator inside a single
// <span data-pito--mini-status-target="…"> so toggling the wrapper also hides
// the separator — no dangling "·" is ever visible.
//
// Events consumed:
//   document#focusin  / document#focusout  — track chatbox focus
//   document#pito:suggest                  — dispatched by autosuggest_controller

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["suggestHint", "chatHint"]

  connect() {
    this._focused      = false
    this._suggestActive = false

    // Bind handlers (store refs so disconnect can remove them)
    this._onFocusIn  = this._handleFocusIn.bind(this)
    this._onFocusOut = this._handleFocusOut.bind(this)
    this._onSuggest  = this._handleSuggest.bind(this)

    document.addEventListener("focusin",      this._onFocusIn)
    document.addEventListener("focusout",     this._onFocusOut)
    document.addEventListener("pito:suggest", this._onSuggest)

    // Compute initial state from active element
    this._focused = this._isChatboxEl(document.activeElement)
    this._suggestActive = false
    this._applyVisibility()
  }

  disconnect() {
    document.removeEventListener("focusin",      this._onFocusIn)
    document.removeEventListener("focusout",     this._onFocusOut)
    document.removeEventListener("pito:suggest", this._onSuggest)
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  _handleFocusIn(e) {
    if (this._isChatboxEl(e.target)) {
      this._focused = true
      this._applyVisibility()
    }
  }

  _handleFocusOut(e) {
    if (this._isChatboxEl(e.target)) {
      this._focused = false
      this._suggestActive = false  // suggestion irrelevant once blurred
      this._applyVisibility()
    }
  }

  _handleSuggest(e) {
    this._suggestActive = !!(e.detail && e.detail.active)
    this._applyVisibility()
  }

  // Returns true if el is the chatbox textarea.
  _isChatboxEl(el) {
    if (!el) return false
    // Primary check: matches the chat-form target attribute
    if (el.matches('[data-pito--chat-form-target="inputField"]')) return true
    // Fallback: inside #pito-chatbox
    if (el.closest && el.closest("#pito-chatbox")) return true
    return false
  }

  _applyVisibility() {
    const showSuggest = this._focused && this._suggestActive
    const showChat    = !this._focused

    if (this.hasSuggestHintTarget) {
      this.suggestHintTarget.classList.toggle("hidden", !showSuggest)
    }
    if (this.hasChatHintTarget) {
      this.chatHintTarget.classList.toggle("hidden", !showChat)
    }
  }
}
