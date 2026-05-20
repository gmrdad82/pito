import { Controller } from "@hotwired/stimulus"

// Beta 4 — Phase F3-B-TOGGLE-FEEDBACK. Visual in-flight feedback for the
// auto-save notification toggles in /settings.
//
// The pane already wraps each toggle in a tiny `form_with` whose
// `auto-submit` controller calls `requestSubmit()` on `change`. The
// browser then ships a `PATCH /settings/notification_toggles/:kind`,
// the controller redirects back to `/settings`, and Turbo follows the
// redirect — re-rendering the whole pane with the new checkbox state.
//
// During the in-flight window (click → redirect lands) the user has
// NO signal that the click was received: the checkbox toggles
// locally, but there's nothing to differentiate "saved" from "yet to
// save". This controller fills that gap by swapping the `[x]` / `[ ]`
// glyph for a braille spinner the moment `change` fires, and
// restoring the glyph on `turbo:submit-end` (defensive — the redirect
// usually replaces the whole DOM before the end event fires, but if
// the submit errored we still want the page to look sane).
//
// Targets:
//
//   glyph    -> the existing `.md-check-indicator` span (CSS-driven
//               `[x]` / `[ ]` content). We toggle `.visibility` so the
//               surrounding flex layout doesn't reflow when the
//               spinner takes its place.
//   spinner  -> the sibling `Tui::IndicatorComponent` render, mounted
//               `hidden` at SSR time. When `hidden` is removed the
//               nested `tui-indicator` Stimulus controller is already
//               connected (it mounted on page load) so the braille
//               frames are already animating in the background — the
//               first visible frame is whatever the spinner is on at
//               unhide time.
//
// The matching markup lives in
// `app/views/settings/_notifications_pane.html.erb`.
export default class extends Controller {
  static targets = ["checkbox", "glyph", "spinner"]

  connect() {
    if (this.hasCheckboxTarget) {
      this.onChange = () => this.startSpinner()
      this.checkboxTarget.addEventListener("change", this.onChange)
    }

    this.formEl = this.element.closest("form")
    if (this.formEl) {
      this.onSubmitEnd = (event) => this.endSpinner(event)
      this.formEl.addEventListener("turbo:submit-end", this.onSubmitEnd)
    }
  }

  disconnect() {
    if (this.hasCheckboxTarget && this.onChange) {
      this.checkboxTarget.removeEventListener("change", this.onChange)
      this.onChange = null
    }
    if (this.formEl && this.onSubmitEnd) {
      this.formEl.removeEventListener("turbo:submit-end", this.onSubmitEnd)
      this.onSubmitEnd = null
      this.formEl = null
    }
  }

  startSpinner() {
    if (this.hasGlyphTarget) {
      this.glyphTarget.style.visibility = "hidden"
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.hidden = false
    }
  }

  endSpinner(_event) {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.hidden = true
    }
    if (this.hasGlyphTarget) {
      this.glyphTarget.style.visibility = "visible"
    }
  }
}
