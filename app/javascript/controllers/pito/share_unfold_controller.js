// pito--share-unfold
//
// Drives the public /share/:uuid chatbox, which is a decoy: the only action is
// "unfold" → open the full conversation. It is NOT a real chat form (the share
// page has no dispatch/cable), so Enter must navigate, not newline.
//
// Behaviour:
//   • `c` (when nothing editable is focused) → focus the textarea.
//   • textarea focused  → swap the hint "c to chat" → "Enter to unfold".
//   • textarea blurred  → swap back to "c to chat".
//   • Enter (no Shift) in the textarea → click the unfold LINK (navigates to the
//     conversation via its href) instead of inserting a newline.
//
// The textarea is prefilled with "unfold" server-side; this controller only
// wires the keys + hint swap. The unfold LINK carries the real conversation URL
// (an <a href>), so navigation works even without JS.
//
// Targets: chatHint (the "c to chat" span), unfoldHint (the "Enter to unfold"
// span), link (the unfold <a>). Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chatHint", "unfoldHint", "link"]

  connect() {
    this.field = this.element.querySelector("textarea")

    this._onKeydown    = (e) => this.#handleFieldKeydown(e)
    this._onFocus      = () => this.#swap(true)
    this._onBlur       = () => this.#swap(false)
    this._onDocKeydown = (e) => this.#focusOnC(e)

    if (this.field) {
      this.field.addEventListener("keydown", this._onKeydown)
      this.field.addEventListener("focus", this._onFocus)
      this.field.addEventListener("blur", this._onBlur)
    }
    document.addEventListener("keydown", this._onDocKeydown)

    this.#swap(document.activeElement === this.field)
  }

  disconnect() {
    if (this.field) {
      this.field.removeEventListener("keydown", this._onKeydown)
      this.field.removeEventListener("focus", this._onFocus)
      this.field.removeEventListener("blur", this._onBlur)
    }
    document.removeEventListener("keydown", this._onDocKeydown)
  }

  // Enter in the field → navigate via the unfold link (never a newline).
  #handleFieldKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    event.preventDefault()
    if (this.hasLinkTarget) this.linkTarget.click()
  }

  // `c` anywhere (outside an editable) → focus the field.
  #focusOnC(event) {
    if (event.key !== "c" || event.metaKey || event.ctrlKey || event.altKey) return

    const ae = document.activeElement
    const editable = ae && (ae.tagName === "INPUT" || ae.tagName === "TEXTAREA" || ae.isContentEditable)
    if (editable) return

    event.preventDefault()
    if (this.field) this.field.focus({ preventScroll: true })
  }

  // Show "Enter to unfold" when focused, "c to chat" when not.
  #swap(focused) {
    if (this.hasChatHintTarget)   this.chatHintTarget.classList.toggle("hidden", focused)
    if (this.hasUnfoldHintTarget) this.unfoldHintTarget.classList.toggle("hidden", !focused)
  }
}
