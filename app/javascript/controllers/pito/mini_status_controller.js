// pito--mini-status
//
// Tracks two dynamic states and toggles hint visibility:
//
//   focused      — is the chatbox textarea currently focused?
//   suggestActive — has autosuggest dispatched pito:suggest with active:true?
//
// Toggle rules:
//   suggestHint visible  ⟺  suggestActive
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

    // Compute initial focused state. Query the chatbox textarea directly so
    // the check is reliable even when terminal-caret's autofocus fires before
    // this controller's focusin listener was registered (both run from the same
    // MutationObserver batch; the focus() call and its focusin event are
    // synchronous, so the event is missed if it fires first). By the time
    // connect() runs, document.activeElement already reflects the focused
    // element, so comparing the textarea to it is the correct approach.
    this._focused = this._isTextareaFocused()
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
      // Safety net: autosuggest dispatches pito:suggest {active:false} when
      // it closes its ghost/palette, but if for any reason it does not (e.g.
      // an unhandled blur path), reset suggestActive here so the hint hides.
      this._suggestActive = false
      this._applyVisibility()
    }
  }

  _handleSuggest(e) {
    this._suggestActive = !!(e.detail && e.detail.active)
    this._applyVisibility()
  }

  // Returns true if the chatbox textarea is the current document.activeElement.
  // Querying the textarea directly (rather than using document.activeElement
  // alone) avoids the primary check relying on an attribute that may not yet
  // be in the DOM at connect() time under certain Turbo restore scenarios.
  _isTextareaFocused() {
    const active = document.activeElement
    if (!active || active === document.body) return false
    return this._isChatboxEl(active)
  }

  // Returns true if el is (or is contained by) the chatbox textarea / chatbox wrapper.
  // Primary check: the textarea carries data-pito--chat-form-target="inputField".
  // Fallback: any element inside #pito-chatbox counts as chatbox-focused (e.g.
  // programmatic focus on a child element from click->focusField).
  _isChatboxEl(el) {
    if (!el) return false
    if (el.matches('[data-pito--chat-form-target="inputField"]')) return true
    if (el.closest && el.closest("#pito-chatbox")) return true
    return false
  }

  _applyVisibility() {
    // Bug 1 fix: chatHint visible only when NOT focused (user cannot type).
    // Bug 2 fix: suggestHint visible whenever a hint/ghost/palette is active,
    //            regardless of focus — tied purely to suggestActive so the hint
    //            disappears exactly when the ghost/palette disappears, not when
    //            focus is lost (focus loss already clears suggestActive via the
    //            safety net in _handleFocusOut).
    const showSuggest = this._suggestActive
    const showChat    = !this._focused

    if (this.hasSuggestHintTarget) {
      this.suggestHintTarget.classList.toggle("hidden", !showSuggest)
    }
    if (this.hasChatHintTarget) {
      this.chatHintTarget.classList.toggle("hidden", !showChat)
    }
  }
}
