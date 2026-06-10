// pito--chatbox-hints
//
// Toggles the hint filter-row spans inside #pito-chatbox:
//   suggestHint  visible  ⟺  a suggestion/hint is active (ghost OR palette)  [pito:suggest]
//   chatHint     visible  ⟺  the chatbox is NOT focused
//   filterHints  visible  ⟺  the chatbox IS focused  (inverse of chatHint: the
//                            shift+tab / shift+space cyclers are only actionable
//                            while focused, so they swap with the `m` chat hint)
//
// Focus tracking is belt-and-suspenders: this controller is on #pito-chatbox
// (the PARENT) and connects BEFORE terminal-caret (a CHILD) runs its autofocus,
// so the focus event can fire before we are listening. We therefore: (1) read
// activeElement on connect, (2) listen to native bubbling focusin/focusout,
// (3) re-check on the next animation frame, and (4) accept the custom pito:focus
// event from terminal-caret.
//
// Visibility note: the hint wrappers must NOT carry a persistent `inline-flex`
// class, because Tailwind's `.inline-flex` and `.hidden` are both display
// utilities with equal specificity — whichever is later in the stylesheet wins,
// and `.inline-flex` was overriding `.hidden`. So we SWAP the display class:
// add `inline-flex` only when visible, `hidden` only when hidden.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["suggestHint", "chatHint", "filterHints"]

  connect() {
    this._suggestActive = false
    this._focused = this.#computeFocused()

    this._onSuggest  = (e) => { this._suggestActive = !!(e.detail && e.detail.active); this._apply() }
    this._onFocus    = (e) => { this._focused = !!(e.detail && e.detail.focused); this._apply() }
    this._onFocusIn  = () => this.#recheck()
    this._onFocusOut = () => this.#recheck()

    document.addEventListener("pito:suggest", this._onSuggest)
    document.addEventListener("pito:focus",   this._onFocus)
    document.addEventListener("focusin",      this._onFocusIn)
    document.addEventListener("focusout",     this._onFocusOut)

    this._apply()
    // Catch the child terminal-caret autofocus that fires right after this connects.
    requestAnimationFrame(() => this.#recheck())
  }

  disconnect() {
    document.removeEventListener("pito:suggest", this._onSuggest)
    document.removeEventListener("pito:focus",   this._onFocus)
    document.removeEventListener("focusin",      this._onFocusIn)
    document.removeEventListener("focusout",     this._onFocusOut)
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  #computeFocused() {
    const a = document.activeElement
    return !!(a && a.closest && a.closest("#pito-chatbox"))
  }

  #recheck() {
    const f = this.#computeFocused()
    if (f !== this._focused) {
      this._focused = f
      this._apply()
    }
  }

  _apply() {
    if (this.hasSuggestHintTarget) this.#setVisible(this.suggestHintTarget, this._suggestActive)
    if (this.hasChatHintTarget)    this.#setVisible(this.chatHintTarget, !this._focused)
    if (this.hasFilterHintsTarget) this.#setVisible(this.filterHintsTarget, this._focused)
  }

  // Swap display classes (never leave inline-flex + hidden fighting).
  #setVisible(el, visible) {
    el.classList.toggle("inline-flex", visible)
    el.classList.toggle("hidden", !visible)
  }
}
