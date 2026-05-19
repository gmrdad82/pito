import { Controller } from "@hotwired/stimulus"

// 2026-05-18 — Reusable 6-box segmented input for a TOTP code.
//
// Mounted on the wrapper element rendered by `TotpCodeInputComponent`.
// Six visible `<input>` boxes + one hidden `<input name="code">` that
// carries the concatenated 6-digit value. The controller:
//
//   - Strips non-digits on every input event, keeps maxlength=1 per
//     box.
//   - Distributes multi-character `input` payloads (1Password /
//     browser-extension autofill that shoves the full 6-digit code
//     into ONE box as a single `input` event with `value.length > 1`)
//     across the boxes starting at the cell that received the input.
//   - Auto-advances focus to the next box on a successful single-digit
//     entry.
//   - Backspace on an empty box steps focus back; on a filled box it
//     clears in place.
//   - ArrowLeft / ArrowRight move focus laterally.
//   - Paste of any string into ANY box strips non-digits, fills the
//     boxes starting AT THE PASTED-INTO INDEX (not always from box 0)
//     so a 6-char paste into box 0 fills all six AND a 3-char paste
//     into box 3 fills 3..5. Focuses the box after the last filled
//     one.
//   - On EVERY change, rewrites the hidden field's value to the
//     concatenated 6-character string (or shorter if not yet full).
//   - Auto-submits the parent form via `form.requestSubmit()` the
//     instant all 6 cells carry a digit — regardless of input path
//     (manual typing, paste, browser-extension autofill, OS one-time-
//     code autofill). The explicit `[verify]` / `[enable 2FA]` submit
//     button on the consumer page remains as a fallback for users who
//     stop short and want to click; auto-submit fires first when the
//     6th digit lands. A guard flag (`_submitted`) prevents a double-
//     submit if the controller re-fires while the form navigation is
//     in flight.
//
// 2026-05-18 (layered autofill catch) — 1Password / Brave native
// autofill via the `autocomplete="one-time-code"` API may bypass the
// `input` event entirely by writing through the
// `HTMLInputElement.prototype.value` setter, which fires no `input`
// event in some browsers. To catch every variant we listen on three
// additional surfaces:
//
//   - `change` on each cell — most autofill implementations fire
//     `change` even when they bypass `input`.
//   - `blur` on each cell — defensive sync; if the autofill landed
//     value silently and the user (or autofill UI) then focuses
//     elsewhere, the blur fires `_syncHidden()` + `_maybeAutoSubmit()`
//     so the hidden field carries the right code and the form posts.
//   - `submit` (capture phase) on the parent form — last-line defense:
//     if 1Password fills + auto-submits the form WITHOUT having ever
//     fired `input` / `change` / `blur` on our cells, the capture-phase
//     listener runs `_syncHidden()` before the submit propagates so the
//     hidden field carries the concatenated 6-digit value.
export default class extends Controller {
  static targets = ["digit", "hidden"]

  connect() {
    // Keep the hidden field in sync with whatever digits are already
    // in the boxes when the controller mounts. Handles the 422
    // re-render path where the boxes might come back blank but the
    // hidden field could have leftover state from a prior partial
    // hydration.
    this._submitted = false
    this._syncHidden()

    // Capture-phase form submit listener — last-line defense against
    // autofill paths that bypass `input` / `change` / `blur` on the
    // cells and submit the form directly. The capture phase runs
    // BEFORE Turbo's own submit listener, so syncing the hidden field
    // here guarantees the right `params[<field>]` lands on the wire.
    // Bound and cached so `disconnect()` can remove the exact same
    // function reference.
    this._form = this.element.closest("form")
    if (this._form) {
      this._onFormSubmit = () => this._syncHidden()
      this._form.addEventListener("submit", this._onFormSubmit, true)
    }
  }

  disconnect() {
    // Tear down the capture-phase submit listener so a Turbo morph or
    // a controller re-mount does not leak duplicated handlers.
    if (this._form && this._onFormSubmit) {
      this._form.removeEventListener("submit", this._onFormSubmit, true)
    }
    this._form = null
    this._onFormSubmit = null
  }

  // Per-box `input` handler. Strips non-digits. Two paths:
  //   - Single digit (the common manual-typing case): keep one digit
  //     in the box, advance focus.
  //   - Multi-character payload (the browser-extension autofill case
  //     where the extension fires a single `input` event with the
  //     full 6-digit string as the new value): distribute the digits
  //     across the boxes starting AT the cell that received the
  //     event, then focus the cell after the last filled one. This
  //     mirrors the paste path so autofill behaves the same as a
  //     clipboard paste.
  onInput(event) {
    const box = event.target
    const idx = this.digitTargets.indexOf(box)
    if (idx < 0) {
      this._syncHidden()
      return
    }

    const cleaned = (box.value || "").replace(/\D/g, "")

    if (cleaned.length <= 1) {
      box.value = cleaned
      if (cleaned && idx < this.digitTargets.length - 1) {
        this.digitTargets[idx + 1].focus()
        this.digitTargets[idx + 1].select()
      }
      this._syncHidden()
      this._maybeAutoSubmit()
      return
    }

    // Multi-char payload — distribute starting at the current cell.
    this._distributeFrom(idx, cleaned)
    this._syncHidden()
    this._maybeAutoSubmit()
  }

  // Per-box `keydown` handler. Backspace on an empty box steps focus
  // back. ArrowLeft / ArrowRight move focus laterally. Enter is a
  // no-op when 6 digits are already present — auto-submit already
  // fired on the 6th digit; Enter on a partial entry falls through to
  // the form's native submit.
  onKeydown(event) {
    const box = event.target
    const idx = this.digitTargets.indexOf(box)

    if (event.key === "Backspace" && !box.value && idx > 0) {
      event.preventDefault()
      const prev = this.digitTargets[idx - 1]
      prev.value = ""
      prev.focus()
      this._syncHidden()
      return
    }

    if (event.key === "ArrowLeft" && idx > 0) {
      event.preventDefault()
      this.digitTargets[idx - 1].focus()
      this.digitTargets[idx - 1].select()
      return
    }

    if (event.key === "ArrowRight" && idx < this.digitTargets.length - 1) {
      event.preventDefault()
      this.digitTargets[idx + 1].focus()
      this.digitTargets[idx + 1].select()
      return
    }
  }

  // Per-box `paste` handler. Reads the clipboard payload, strips
  // non-digits, fills boxes starting AT THE PASTED-INTO INDEX (so a
  // 6-char paste into box 0 fills all 6; a 3-char paste into box 3
  // fills cells 3..5). Focuses the box right after the last filled
  // one (or the last box if the distribution reached the end).
  onPaste(event) {
    event.preventDefault()
    const raw = (event.clipboardData || window.clipboardData)?.getData("text") || ""
    const cleaned = raw.replace(/\D/g, "")
    const idx = this.digitTargets.indexOf(event.target)
    const startAt = idx >= 0 ? idx : 0
    this._distributeFrom(startAt, cleaned)
    this._syncHidden()
    this._maybeAutoSubmit()
  }

  // Per-box `blur` handler — defensive sync for autofill paths that
  // wrote the cell's value silently (no `input`, no `change`). We do
  // NOT redistribute on blur because that would interfere with normal
  // user navigation (Tab / Shift+Tab from a half-filled cell). We
  // ONLY re-write the hidden field and re-check the auto-submit
  // condition.
  onCellBlur() {
    this._syncHidden()
    this._maybeAutoSubmit()
  }

  // Private — write `digits` into `this.digitTargets` starting at
  // `startIdx`. Stops when either the digits run out or the cells
  // run out. Focuses the cell after the last filled one (or the last
  // cell if the distribution reached the end).
  _distributeFrom(startIdx, digits) {
    if (!digits) return
    const cells = this.digitTargets
    const limit = Math.min(digits.length, cells.length - startIdx)
    for (let i = 0; i < limit; i++) {
      cells[startIdx + i].value = digits[i]
    }
    const lastFilled = startIdx + limit - 1
    const next = Math.min(lastFilled + 1, cells.length - 1)
    cells[next]?.focus()
    if (lastFilled + 1 < cells.length) {
      cells[next]?.select()
    }
  }

  // Private — concatenate every box's value into a single string and
  // write it onto the hidden field so a form submit carries the
  // expected `params[<field>]` shape.
  _syncHidden() {
    if (!this.hasHiddenTarget) return
    this.hiddenTarget.value = this.digitTargets
      .map((box) => box.value || "")
      .join("")
  }

  // Private — auto-submit the parent form once all 6 cells carry a
  // digit. Uses `requestSubmit()` so the form's submit-event
  // listeners (Turbo, our own interceptors) fire — `form.submit()`
  // would bypass them. Guarded by `_submitted` so a re-fire during
  // the in-flight navigation does not double-post.
  _maybeAutoSubmit() {
    if (this._submitted) return
    const code = this.digitTargets.map((box) => box.value || "").join("")
    if (code.length !== this.digitTargets.length) return
    if (!/^\d+$/.test(code)) return

    const form = this.element.closest("form")
    if (!form) return

    this._submitted = true
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }
}
