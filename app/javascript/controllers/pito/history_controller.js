// pito--history
//
// Shell-style input history for the chatbox textarea (↑ = older, ↓ = newer).
//
// Mounted on #pito-chatbox alongside pito--autosuggest and pito--draft.
// On the start screen the history value will be an empty array, making the
// controller effectively inert.
//
// Values:
//   entries — JSON array of previously-sent input_text strings, newest first.
//
// Behaviour:
//   - Maintains an index (-1 = current draft).
//   - ArrowUp: step toward older entries (higher index).
//   - ArrowDown: step toward newer entries (lower index), restoring the
//     preserved draft when the index returns to -1.
//   - Guards (let event pass without consuming it):
//       • The autosuggest palette is open (.pito-autosuggest-palette:not(.hidden)).
//       • The sidebar is open (#pito-sidebar has child elements).
//       • For ArrowUp: caret is NOT on the first visual line (i.e. textarea
//         contains a newline AND caret position > 0).
//       • For ArrowDown: caret is NOT on the last visual line (i.e. textarea
//         contains a newline AND caret position < value length).
//   - On applying an entry: sets textarea.value, moves caret to end, and
//     dispatches a synthetic `input` event so other controllers (type-fx,
//     terminal-caret, draft) re-render.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { entries: Array }

  connect() {
    this._index = -1       // -1 = "at current draft"
    this._draft = ""       // preserved draft text

    this._onKeydown = this.#onKeydown.bind(this)
    this.element.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    this.element.removeEventListener("keydown", this._onKeydown)
  }

  // ── Private ────────────────────────────────────────────────────────────────

  get #entries() {
    return this.entriesValue || []
  }

  #onKeydown(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return

    const field = this.element.querySelector("textarea")
    if (!field) return

    // Guard: autosuggest palette is open.
    if (document.querySelector(".pito-autosuggest-palette:not(.hidden)")) return

    // Guard: sidebar is open (has child elements).
    const sidebar = document.getElementById("pito-sidebar")
    if (sidebar && sidebar.children.length > 0) return

    const entries = this.#entries
    if (entries.length === 0) return

    const value  = field.value
    const caret  = field.selectionStart
    const hasNewline = value.includes("\n")

    if (event.key === "ArrowUp") {
      // Guard: for multi-line content, only consume if caret is at position 0
      // (i.e. on the first visual line).
      if (hasNewline && caret > 0) return

      const nextIndex = this._index + 1
      if (nextIndex >= entries.length) return   // already at oldest

      if (this._index === -1) {
        // Preserve the current draft before stepping into history.
        this._draft = value
      }

      this._index = nextIndex
      this.#applyEntry(field, entries[this._index])
      event.preventDefault()

    } else {
      // ArrowDown
      // Guard: for multi-line content, only consume if caret is at the end.
      if (hasNewline && caret < value.length) return

      if (this._index === -1) return   // already at current draft

      const nextIndex = this._index - 1

      if (nextIndex < 0) {
        // Return to preserved draft.
        this._index = -1
        this.#applyEntry(field, this._draft)
      } else {
        this._index = nextIndex
        this.#applyEntry(field, entries[this._index])
      }
      event.preventDefault()
    }
  }

  #applyEntry(field, text) {
    field.value = text
    // Move caret to end.
    field.selectionStart = field.selectionEnd = text.length
    // Notify other controllers (type-fx overlay, terminal-caret, draft autosave).
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
