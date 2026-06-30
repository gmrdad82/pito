// pito--autosize
//
// Grows the chatbox <textarea> to fit its (soft-wrapped) content, and — when
// asked — autofocuses it with the caret at the end of any restored draft.
//
// This is the FUNCTIONAL remainder of the old pito--terminal-caret controller.
// The bespoke block-caret RENDER (hidden mirror, inverted block span, comet
// trail) was removed in favour of the browser's native caret styled as a block
// via CSS (`caret-shape: block`); but the textarea still has to auto-grow and
// the chatbox still has to take focus on load — those concerns live here now,
// cleanly separated from any caret painting.
//
// DOM contract (chatbox ERB):
//   <div class="pito-chatbox__field-wrap"
//        data-controller="… pito--autosize"
//        data-pito--autosize-autofocus-value="true">
//     <textarea data-pito--autosize-target="field" …></textarea>
//   </div>
//
// Values:
//   autofocus (Boolean) — focus the field on connect and move the caret to the
//                         end of its value (so a restored draft continues where
//                         the user left off).
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field"]
  static values  = { autofocus: Boolean }

  connect() {
    this.field = this.hasFieldTarget ? this.fieldTarget : this.element
    if (!this.field || this.field.tagName !== "TEXTAREA") return

    this._onInput = () => this.grow()
    this.field.addEventListener("input", this._onInput)

    // Re-grow when layout resizes the field (e.g. sidebar opens/closes, the
    // viewport changes width). Guarded for jsdom (no ResizeObserver).
    if (typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(() => this.grow())
      this._resizeObserver.observe(this.field)
    }

    this.grow()

    if (this.autofocusValue) {
      this.field.focus({ preventScroll: true })
      // A restored draft (or a conversation switch) re-renders the field with its
      // saved text; focus() alone leaves the caret at position 0. Move it to the
      // end so the user continues typing from where they left off.
      const end = this.field.value.length
      this.field.selectionStart = this.field.selectionEnd = end
    }
  }

  disconnect() {
    if (this._onInput) this.field?.removeEventListener("input", this._onInput)
    this._resizeObserver?.disconnect()
  }

  // Grow a textarea to fit its content. Reset to "auto" first so it can also
  // SHRINK when text is deleted, then lock to the scroll height.
  grow() {
    if (!this.field) return
    this.field.style.height = "auto"
    this.field.style.height = `${this.field.scrollHeight}px`
  }
}
