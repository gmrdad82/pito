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
//               `[x]` / `[ ]` content, 3ch wide). We toggle the
//               `hidden` attribute (which maps to `display: none` via
//               the user-agent stylesheet) so the glyph leaves the
//               inline flow entirely while the spinner is showing.
//   spinner  -> the sibling `Tui::IndicatorComponent` render wrapped
//               in literal `[` and `]` brackets so the spinner slot is
//               exactly 3 characters wide — the same width as `[x]`.
//               Mounted `hidden` at SSR time. When `hidden` is removed
//               the nested `tui-indicator` Stimulus controller is
//               already connected (it mounted on page load) so the
//               braille frames are already animating in the
//               background — the first visible frame is whatever the
//               spinner is on at unhide time.
//
// Because both glyph and spinner are 3ch wide and only one is in the
// flow at a time, the surrounding label text never shifts on toggle.
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
      this.glyphTarget.hidden = true
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.hidden = false
    }
    // FB-165 — while the async save is in flight, drop this toggle out
    // of the j/k focus list. The wrapping `[data-tui-focusable]` ancestor
    // gets `data-tui-focusable-disabled="yes"`; the cursor controller's
    // filter skips disabled focusables. Restored on `turbo:submit-end`
    // (or whenever the page re-renders post-redirect, since the new
    // markup ships without the disabled flag).
    this.toggleFocusableDisabled(true)
  }

  endSpinner(_event) {
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.hidden = true
    }
    if (this.hasGlyphTarget) {
      this.glyphTarget.hidden = false
    }
    this.toggleFocusableDisabled(false)
  }

  toggleFocusableDisabled(disabled) {
    const wrapper = this.element.closest("[data-tui-focusable]")
    if (!wrapper) return
    if (disabled) {
      wrapper.dataset.tuiFocusableDisabled = "yes"
    } else {
      delete wrapper.dataset.tuiFocusableDisabled
    }
  }
}
