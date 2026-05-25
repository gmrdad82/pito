import { Controller } from "@hotwired/stimulus"

// backup-code-input — 8-box segmented input for alphanumeric backup auth codes.
//
// Mounted on the wrapper element rendered by `Pito::BackupCodeInputComponent`.
// Eight visible `<input type="text">` boxes + one hidden `<input name="backup_code">`
// that carries the concatenated 8-char alphanumeric string.
//
// Behavior mirrors totp-code-input but:
//   - Accepts alphanumeric (a-z, A-Z, 0-9); strips all other chars.
//   - Lowercases input on entry (codes are always lowercase).
//   - Does NOT auto-submit — backup codes require the user to press [log in].
//   - Distributes paste payloads starting at the cell that received the paste.
//   - Backspace on an empty box steps focus back.
//   - ArrowLeft / ArrowRight move focus laterally.
//   - On every change, rewrites the hidden field to the concatenated 8-char string.
//
// Capture-phase form submit listener syncs the hidden field as a last-line defense
// against autofill paths that bypass input/change/blur.
export default class extends Controller {
  static targets = ["char", "hidden"]
  static values  = { field: String }

  connect() {
    this._syncHidden()

    this._form = this.element.closest("form")
    if (this._form) {
      this._onFormSubmit = () => this._syncHidden()
      this._form.addEventListener("submit", this._onFormSubmit, true)
    }
  }

  disconnect() {
    if (this._form && this._onFormSubmit) {
      this._form.removeEventListener("submit", this._onFormSubmit, true)
    }
    this._form = null
    this._onFormSubmit = null
  }

  // Per-box `input` handler. Strips non-alphanumeric chars, lowercases,
  // keeps maxlength=1 per box. Distributes multi-char payloads (e.g. password
  // manager autofill writing full 8-char string into one box).
  onInput(event) {
    const box = event.target
    const idx = this.charTargets.indexOf(box)
    if (idx < 0) {
      this._syncHidden()
      return
    }

    const cleaned = this._sanitize(box.value)

    if (cleaned.length <= 1) {
      box.value = cleaned
      if (cleaned && idx < this.charTargets.length - 1) {
        this.charTargets[idx + 1].focus()
        this.charTargets[idx + 1].select()
      }
      this._syncHidden()
      return
    }

    // Multi-char payload — distribute starting at the current cell.
    this._distributeFrom(idx, cleaned)
    this._syncHidden()
  }

  // Per-box `keydown` handler. Backspace on empty steps back. Arrows move laterally.
  onKeydown(event) {
    const box = event.target
    const idx = this.charTargets.indexOf(box)

    if (event.key === "Backspace" && !box.value && idx > 0) {
      event.preventDefault()
      const prev = this.charTargets[idx - 1]
      prev.value = ""
      prev.focus()
      this._syncHidden()
      return
    }

    if (event.key === "ArrowLeft" && idx > 0) {
      event.preventDefault()
      this.charTargets[idx - 1].focus()
      this.charTargets[idx - 1].select()
      return
    }

    if (event.key === "ArrowRight" && idx < this.charTargets.length - 1) {
      event.preventDefault()
      this.charTargets[idx + 1].focus()
      this.charTargets[idx + 1].select()
      return
    }
  }

  // Per-box `paste` handler. Reads clipboard, strips non-alphanumeric,
  // fills boxes starting AT THE PASTED-INTO INDEX.
  onPaste(event) {
    event.preventDefault()
    const raw = (event.clipboardData || window.clipboardData)?.getData("text") || ""
    const cleaned = this._sanitize(raw)
    const idx = this.charTargets.indexOf(event.target)
    const startAt = idx >= 0 ? idx : 0
    this._distributeFrom(startAt, cleaned)
    this._syncHidden()
  }

  // Per-box `blur` handler — defensive sync for autofill paths that wrote
  // the cell value silently.
  onCellBlur() {
    this._syncHidden()
  }

  // Private — strip non-alphanumeric chars and lowercase the result.
  _sanitize(str) {
    return (str || "").replace(/[^a-z0-9]/gi, "").toLowerCase()
  }

  // Private — write `chars` into `this.charTargets` starting at `startIdx`.
  _distributeFrom(startIdx, chars) {
    if (!chars) return
    const cells = this.charTargets
    const limit = Math.min(chars.length, cells.length - startIdx)
    for (let i = 0; i < limit; i++) {
      cells[startIdx + i].value = chars[i]
    }
    const lastFilled = startIdx + limit - 1
    const next = Math.min(lastFilled + 1, cells.length - 1)
    cells[next]?.focus()
    if (lastFilled + 1 < cells.length) {
      cells[next]?.select()
    }
  }

  // Private — concatenate all box values into the hidden field.
  _syncHidden() {
    if (!this.hasHiddenTarget) return
    this.hiddenTarget.value = this.charTargets
      .map((box) => box.value || "")
      .join("")
  }
}
