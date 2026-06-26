// pito--history
//
// Shell-style (oh-my-zsh) PREFIX-matched input history for the chatbox textarea
// (↑ = older, ↓ = newer), with in-place replacement — NOT a palette / autosuggest.
//
// Mounted on #pito-chatbox alongside pito--suggestions and pito--draft.
// On the start screen the history value will be an empty array, making the
// controller effectively inert.
//
// Values:
//   entries — JSON array of previously-sent input strings, newest first.
//
// Behaviour (oh-my-zsh prefix search):
//   - The FIRST ↑ snapshots the current buffer as the search PREFIX and filters
//     history to the entries that startsWith(prefix). Typing "/conf" then ↑ walks
//     only "/config…" entries; an empty buffer matches everything.
//   - ↑ steps toward older matches, ↓ toward newer, restoring the snapshot draft
//     when the index returns to -1. NO WRAP at either end (stops at the oldest
//     match / the draft).
//   - Typing any character ENDS the recall session (a real `input` event clears
//     the snapshot); the next ↑ re-snapshots from the now-current buffer.
//   - No timer / no pending-commit state: the shown value is always the live value.
//   - Guards (let the event pass without consuming it):
//       • The suggestions palette is open (.pito-suggestions-palette:not(.hidden)).
//       • The sidebar is open (#pito-sidebar has child elements).
//       • For ↑: caret is NOT on the first visual line (textarea has a newline AND
//         caret > 0). For ↓: caret is NOT on the last visual line.
//   - On applying an entry: sets textarea.value, moves caret to end, and
//     dispatches a synthetic `input` event so other controllers (type-fx,
//     terminal-caret, draft) re-render. That synthetic event is flagged so it does
//     NOT count as a user edit (which would end the recall session).
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { entries: Array }

  connect() {
    this._index    = -1      // -1 = "at the snapshot draft"
    this._draft    = ""      // preserved buffer text when recall began
    this._prefix   = null    // null = no active recall session
    this._matches  = null    // entries.startsWith(prefix), newest-first
    this._applying = false   // true while we dispatch our own synthetic input

    this._onKeydown = this.#onKeydown.bind(this)
    this.element.addEventListener("keydown", this._onKeydown)

    // A real user edit ends the recall session. We listen for `input` on the
    // chatbox; our own synthetic input (from #applyEntry) is ignored via the
    // _applying flag.
    this._onInput = this.#onInput.bind(this)
    this.element.addEventListener("input", this._onInput)

    // Capture the submitted value before the chat-form clears the textarea.
    // We listen on the nearest ancestor <form> in capture phase so we run
    // before the chat-form's submit handler empties the field.
    this._form = this.element.closest("form")
    if (this._form) {
      this._onSubmit = this.#onSubmit.bind(this)
      this._form.addEventListener("submit", this._onSubmit, { capture: true })
    }
  }

  disconnect() {
    this.element.removeEventListener("keydown", this._onKeydown)
    this.element.removeEventListener("input", this._onInput)
    if (this._form && this._onSubmit) {
      this._form.removeEventListener("submit", this._onSubmit, { capture: true })
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  // Live entries: starts as the server-rendered value; prepended on each send.
  // We keep our own _entries array so we don't mutate the Stimulus value object
  // on every keystroke and to allow deduplication / cap logic.
  get #entries() {
    // Initialise once from the server-rendered Stimulus value.
    if (!this._entries) {
      this._entries = this.entriesValue || []
    }
    return this._entries
  }

  // End any active recall session so the next ↑ re-snapshots the current buffer.
  #resetRecall() {
    this._index   = -1
    this._prefix  = null
    this._matches = null
  }

  #onInput() {
    // Ignore the synthetic input we dispatch while applying a recalled entry.
    if (this._applying) return
    // A real user edit ends the recall session.
    this.#resetRecall()
  }

  #onSubmit() {
    const field = this.element.querySelector("textarea")
    if (!field) return

    const text = field.value.trim()
    if (!text) return

    const entries = this.#entries

    // Dedupe consecutive duplicates (don't add if identical to the current newest).
    if (entries.length === 0 || entries[0] !== text) {
      // Prepend newest-first; cap at 50.
      this._entries = [text, ...entries].slice(0, 50)
    }

    // Reset so the next ↑ starts a fresh search from the (cleared) buffer.
    this._draft = ""
    this.#resetRecall()
  }

  #onKeydown(event) {
    if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return
    // Shift+Arrow is reserved for paging the scrollback (pito--scrollback) —
    // it must NOT also step through input history.
    if (event.shiftKey) return

    const field = this.element.querySelector("textarea")
    if (!field) return

    // Guard: autosuggest palette is open.
    if (document.querySelector(".pito-suggestions-palette:not(.hidden)")) return

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

      // Start a recall session on the first ↑: snapshot the buffer as the prefix
      // and filter history to the matching entries (empty prefix → all entries).
      if (this._prefix === null) {
        this._prefix  = value
        this._draft   = value
        this._matches = entries.filter((e) => e.startsWith(this._prefix))
      }

      const nextIndex = this._index + 1
      if (nextIndex >= this._matches.length) return   // no match / at oldest (no wrap)

      this._index = nextIndex
      this.#applyEntry(field, this._matches[this._index])
      event.preventDefault()

    } else {
      // ArrowDown
      // Guard: for multi-line content, only consume if caret is at the end.
      if (hasNewline && caret < value.length) return

      if (this._index === -1) return   // already at the snapshot draft

      const nextIndex = this._index - 1

      if (nextIndex < 0) {
        // Return to the snapshot draft (keep the prefix so a further ↑ continues).
        this._index = -1
        this.#applyEntry(field, this._draft)
      } else {
        this._index = nextIndex
        this.#applyEntry(field, this._matches[this._index])
      }
      event.preventDefault()
    }
  }

  #applyEntry(field, text) {
    // Flag so the resulting `input` event is not treated as a user edit (which
    // would end the recall session via #onInput).
    this._applying = true
    field.value = text
    // Move caret to end.
    field.selectionStart = field.selectionEnd = text.length
    // Notify other controllers (type-fx overlay, terminal-caret, draft autosave).
    field.dispatchEvent(new Event("input", { bubbles: true }))
    this._applying = false
  }
}
