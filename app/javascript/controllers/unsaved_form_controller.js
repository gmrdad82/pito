import { Controller } from "@hotwired/stimulus"

// Phase B post-commit (2026-05-04) — Note revamp.
//
// "Leave page with unsaved changes" navigation guard via the browser-native
// `beforeunload` event. When the form is dirty, navigating away (back
// button, link click that turns into a top-level navigation, tab close,
// reload) triggers the browser's own "Leave site?" dialog. Each browser
// renders its own UI; the message text we set is largely ignored.
//
// CARVE-OUT: this is the documented exception to the "no JS confirms"
// hard rule (see CLAUDE.md). `beforeunload` is NOT `window.confirm` —
// the browser renders the dialog itself; the page does not interrupt
// user action mid-click. Any other "are you sure?" guard must go through
// `ConfirmModalComponent` or the action-confirmation page.
//
// Behavior:
// - On connect, snapshot the form's serialized state.
// - On any `input` / `change` inside the form, compare against the snapshot;
//   if different, mark dirty.
// - On `beforeunload`, if dirty, set `event.returnValue` to trigger the
//   native dialog.
// - On submit, clear the dirty flag BEFORE the navigation so a successful
//   redirect doesn't trigger the guard.
export default class extends Controller {
  connect() {
    this._dirty = false
    this._snapshot = this._serializeForm()

    this._onInput = () => this._checkDirty()
    this._onSubmit = () => { this._dirty = false }
    this._onBeforeUnload = (event) => {
      if (!this._dirty) return undefined
      // Modern Chromium / Firefox per the HTML Living Standard require
      // `preventDefault()` to actually surface the leave-site prompt.
      // `returnValue = ""` is kept for legacy fallback (older WebKit).
      // The dialog text is browser-controlled; our string is ignored.
      event.preventDefault()
      event.returnValue = ""
      return ""
    }

    this.element.addEventListener("input", this._onInput)
    this.element.addEventListener("change", this._onInput)
    this.element.addEventListener("submit", this._onSubmit)
    window.addEventListener("beforeunload", this._onBeforeUnload)
  }

  disconnect() {
    this.element.removeEventListener("input", this._onInput)
    this.element.removeEventListener("change", this._onInput)
    this.element.removeEventListener("submit", this._onSubmit)
    window.removeEventListener("beforeunload", this._onBeforeUnload)
  }

  _checkDirty() {
    const current = this._serializeForm()
    this._dirty = current !== this._snapshot
  }

  // Stable string snapshot of every text/textarea/select/checkbox value.
  // FormData would handle most of this but doesn't include unchecked
  // checkboxes; we fold over `elements` directly so the snapshot is total.
  _serializeForm() {
    const parts = []
    const elements = this.element.elements
    if (!elements) return ""
    for (const el of elements) {
      if (!el.name) continue
      if (el.type === "checkbox" || el.type === "radio") {
        parts.push(`${el.name}=${el.checked ? "1" : "0"}`)
      } else if (el.type === "file") {
        // Skip files — beforeunload fires AFTER the user picks a file in
        // some browsers, and we can't compare File objects meaningfully.
        continue
      } else {
        parts.push(`${el.name}=${el.value}`)
      }
    }
    return parts.join("&")
  }
}
