import { Controller } from "@hotwired/stimulus"

// 2026-05-11 — Layout-level TOTP verification dialog controller.
//
// Lives on the `<dialog id="totp-verification-modal">` element rendered
// by `shared/_totp_verification_modal`. The per-form `totp-modal`
// controller (see `totp_modal_controller.js`) intercepts the submit of
// a gated settings form, hands the form reference off to THIS controller
// via `prepare(form)`, and opens the dialog. As soon as all 6 digits
// are present (typed or pasted) the controller injects a hidden
// `totp_code` input into the pending form and re-submits it.
//
// Segmented input UX (Slack-style):
//   - 6 boxes (this.boxTargets), maxlength=1 each.
//   - Typing a digit auto-advances focus to the next box.
//   - Backspace on an empty box steps focus back; on a filled box,
//     clears it in place.
//   - Paste of a 6-char numeric string into ANY box fills all 6 from
//     the left and focuses the box after the last filled one.
//   - Auto-submit: the instant all 6 boxes carry a digit (typed or
//     pasted) the controller injects the hidden `totp_code` input and
//     submits the pending form. No `[confirm]` button, no Enter step.
//
// Close paths:
//   - `[cancel]` → close() (form NOT submitted).
//   - Backdrop click → clickOutside() → close().
//   - Esc → onKeydown() → close().
//
// NO JS `confirm()` / `alert()` / `prompt()` / `data-turbo-confirm`
// (CLAUDE.md hard rule). The dialog IS the confirmation surface.
export default class extends Controller {
  static targets = ["box"]

  connect() {
    // No form pending until a trigger calls prepare(). The reference is
    // held on `this._pendingForm` so the dialog only ever submits the
    // form the user actually clicked `[update]` on.
    this._pendingForm = null
  }

  // Called by the per-form totp-modal controller when the user clicks
  // `[update]` on a 2FA-required form. Stores the form reference, wipes
  // any leftover digits, opens the dialog, and focuses the first box.
  prepare(form) {
    this._pendingForm = form
    this._reset()
    this.element.showModal()
    // Defer the focus call so the dialog has time to paint before the
    // browser tries to move the caret into a hidden input.
    queueMicrotask(() => {
      if (this.boxTargets.length > 0) {
        this.boxTargets[0].focus()
      }
    })
  }

  // Per-box `input` handler. Strips non-digits, auto-advances focus to
  // the next box on a successful digit entry, then auto-submits the
  // moment all 6 boxes carry a digit.
  onInput(event) {
    const box = event.target
    const digit = (box.value || "").replace(/\D/g, "").slice(-1)
    box.value = digit
    if (digit) {
      const idx = this.boxTargets.indexOf(box)
      if (idx >= 0 && idx < this.boxTargets.length - 1) {
        this.boxTargets[idx + 1].focus()
        this.boxTargets[idx + 1].select()
      }
    }
    this._maybeAutoSubmit()
  }

  // Per-box `keydown` handler. Backspace on an empty box steps focus
  // back. ArrowLeft / ArrowRight move focus laterally. Enter is a
  // no-op now — auto-submit fires the instant the 6th digit lands.
  onKeydown(event) {
    const box = event.target
    const idx = this.boxTargets.indexOf(box)

    if (event.key === "Backspace" && !box.value && idx > 0) {
      event.preventDefault()
      const prev = this.boxTargets[idx - 1]
      prev.value = ""
      prev.focus()
      return
    }

    if (event.key === "ArrowLeft" && idx > 0) {
      event.preventDefault()
      this.boxTargets[idx - 1].focus()
      this.boxTargets[idx - 1].select()
      return
    }

    if (event.key === "ArrowRight" && idx < this.boxTargets.length - 1) {
      event.preventDefault()
      this.boxTargets[idx + 1].focus()
      this.boxTargets[idx + 1].select()
      return
    }

    if (event.key === "Enter") {
      // Swallow Enter so it never re-submits a parent form, but do not
      // duplicate the auto-submit path — that already fired when the
      // 6th digit landed via `onInput`.
      event.preventDefault()
    }
  }

  // Per-box `paste` handler. Reads the clipboard payload, strips
  // non-digits, and fills boxes from the left. Focuses the box right
  // after the last filled one (or stays on the last box if all 6
  // filled), then auto-submits if 6 digits were pasted.
  onPaste(event) {
    event.preventDefault()
    const raw = (event.clipboardData || window.clipboardData)?.getData("text") || ""
    const digits = raw.replace(/\D/g, "").slice(0, this.boxTargets.length).split("")
    this.boxTargets.forEach((box, i) => {
      box.value = digits[i] || ""
    })
    const next = Math.min(digits.length, this.boxTargets.length - 1)
    this.boxTargets[next]?.focus()
    if (next < digits.length) {
      this.boxTargets[next]?.select()
    }
    this._maybeAutoSubmit()
  }

  // Private — submit the pending form once all 6 boxes carry a digit.
  // Injects a hidden `totp_code` input (replacing any prior copy) and
  // submits via `requestSubmit()` so the form's listeners (Turbo, our
  // own interceptor) fire. The dialog stays open while the browser
  // navigates so a backend reject re-renders the page and the user
  // sees the same flash they would see on the inline-input path.
  _maybeAutoSubmit() {
    const code = this._code()
    if (code.length !== this.boxTargets.length) return
    if (!/^\d+$/.test(code)) return

    const form = this._pendingForm
    if (!form) {
      this.close()
      return
    }

    // Drop any leftover `totp_code` field on the form (defensive — the
    // ERB partials no longer render one, but a re-opened modal must
    // not stack multiple values).
    form.querySelectorAll('input[name="totp_code"]').forEach((node) => node.remove())

    const hidden = document.createElement("input")
    hidden.type  = "hidden"
    hidden.name  = "totp_code"
    hidden.value = code
    form.appendChild(hidden)

    // Mark the form so the per-form `totp-modal` controller's submit
    // interceptor lets this go through without re-opening the dialog.
    form.dataset.totpModalVerifiedValue = "yes"

    // Use `requestSubmit()` when available so the form's submit-event
    // listeners (Turbo, our own interceptor) fire — `form.submit()`
    // bypasses them. Fall back to .submit() for ancient browsers.
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }

    this.element.close()
  }

  close(event) {
    if (event) event.preventDefault()
    this.element.close()
    this._pendingForm = null
  }

  clickOutside(event) {
    if (event.target === this.element) {
      this.close(event)
    }
  }

  // Dialog-level keydown — Esc closes (native <dialog> already does
  // this but we add the guard so embedded forms can't swallow the
  // event).
  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close(event)
    }
  }

  // Private — concatenate every box's value into a single string.
  _code() {
    return this.boxTargets.map((box) => box.value || "").join("")
  }

  // Private — wipe every box back to empty. Called on every prepare()
  // so the dialog never reopens with stale digits.
  _reset() {
    this.boxTargets.forEach((box) => { box.value = "" })
  }
}
