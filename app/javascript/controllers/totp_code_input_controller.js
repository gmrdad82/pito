import { Controller } from "@hotwired/stimulus"

// 2026-05-18 — Reusable 6-box segmented input for a TOTP code.
//
// Mounted on the wrapper element rendered by `TotpCodeInputComponent`.
// Six visible `<input>` boxes + one hidden `<input name="code">` that
// carries the concatenated 6-digit value. The controller:
//
//   - Strips non-digits on every input event, keeps maxlength=1 per
//     box.
//   - Auto-advances focus to the next box on a successful digit
//     entry.
//   - Backspace on an empty box steps focus back; on a filled box it
//     clears in place.
//   - ArrowLeft / ArrowRight move focus laterally.
//   - Paste of any string into ANY box strips non-digits, fills the
//     boxes from the left, focuses the box after the last filled one.
//   - On EVERY change, rewrites the hidden field's value to the
//     concatenated 6-character string (or shorter if not yet full).
//     A form submit (Enter inside a box, click on the page's own
//     `[verify]` / `[enable 2FA]` button) sends `params[<field>]`
//     exactly as if a single bare `<input name="code">` had been
//     submitted.
//
// Unlike the layout-level `totp-modal-dialog` controller this one
// does NOT auto-submit the form on the 6th digit. The enrollment
// page (`settings/security/totps/new`) and the login challenge page
// (`login/totp_challenges/show`) both render an explicit submit
// button; auto-submit would race with deliberate clicks and surprise
// users who paste then want to review.
export default class extends Controller {
  static targets = ["digit", "hidden"]

  connect() {
    // Keep the hidden field in sync with whatever digits are already
    // in the boxes when the controller mounts. Handles the 422
    // re-render path where the boxes might come back blank but the
    // hidden field could have leftover state from a prior partial
    // hydration.
    this._syncHidden()
  }

  // Per-box `input` handler. Strips non-digits, keeps at most one
  // digit in the box, auto-advances focus to the next box on a
  // successful digit entry, then rewrites the hidden field.
  onInput(event) {
    const box = event.target
    const digit = (box.value || "").replace(/\D/g, "").slice(-1)
    box.value = digit
    if (digit) {
      const idx = this.digitTargets.indexOf(box)
      if (idx >= 0 && idx < this.digitTargets.length - 1) {
        this.digitTargets[idx + 1].focus()
        this.digitTargets[idx + 1].select()
      }
    }
    this._syncHidden()
  }

  // Per-box `keydown` handler. Backspace on an empty box steps focus
  // back. ArrowLeft / ArrowRight move focus laterally. Enter falls
  // through so the parent form's native submit runs (the page has an
  // explicit submit button but Enter inside a numeric input should
  // submit the form, the same affordance a single bare input gave).
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
  // non-digits, fills boxes from the left. Focuses the box right
  // after the last filled one (or the last box if all 6 filled).
  onPaste(event) {
    event.preventDefault()
    const raw = (event.clipboardData || window.clipboardData)?.getData("text") || ""
    const digits = raw.replace(/\D/g, "").slice(0, this.digitTargets.length).split("")
    this.digitTargets.forEach((box, i) => {
      box.value = digits[i] || ""
    })
    const next = Math.min(digits.length, this.digitTargets.length - 1)
    this.digitTargets[next]?.focus()
    if (next < digits.length) {
      this.digitTargets[next]?.select()
    }
    this._syncHidden()
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
}
