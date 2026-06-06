// pito--draft
//
// Autosaves the chatbox textarea to the server on every input event (typing OR
// suggestion-accept — both dispatch `input`), debounced ~800ms.
//
// Mounted on #pito-chatbox (the same element as pito--suggestions) via the
// conversation show view only. The start screen and 404 page do NOT include
// this controller, so they never autosave.
//
// Values:
//   uuid — conversation UUID, used to build the PATCH endpoint.
//
// Behaviour:
//   - On `input`, debounce then PATCH /chat/<uuid> with { draft: <value> }.
//   - Skips redundant saves (no PATCH if value unchanged since last save).
//   - Skips empty→empty (no PATCH if last saved was empty/null and field is empty).
//   - Cancels pending debounce on disconnect.
//   - Listens for the form submit to cancel pending debounce on send.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 800

export default class extends Controller {
  static values = { uuid: String }

  connect() {
    // Guard: no-op if uuid is somehow blank (shouldn't happen on conversation page).
    if (!this.uuidValue) return

    this._lastSaved = null   // null = "we haven't saved anything yet"
    this._timer     = null

    this._onInput  = this.#onInput.bind(this)
    this._onSubmit = this.#cancelPending.bind(this)

    // Listen on the chatbox wrapper element (bubbled from textarea).
    this.element.addEventListener("input", this._onInput)

    // Cancel pending debounce when the form is submitted so a save with empty
    // value doesn't fire after the field is already cleared by chat-form.
    const form = this.element.closest("form") || document.querySelector("form.chatbox-form")
    if (form) {
      form.addEventListener("submit", this._onSubmit)
      this._form = form
    }
  }

  disconnect() {
    this.#cancelPending()
    this.element.removeEventListener("input", this._onInput)
    if (this._form) {
      this._form.removeEventListener("submit", this._onSubmit)
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  #onInput(event) {
    if (!this.uuidValue) return

    // Only care about events from the textarea itself.
    if (event.target.tagName !== "TEXTAREA") return

    this.#cancelPending()
    this._timer = setTimeout(() => {
      this._timer = null
      this.#save(event.target.value)
    }, DEBOUNCE_MS)
  }

  #cancelPending() {
    if (this._timer !== null) {
      clearTimeout(this._timer)
      this._timer = null
    }
  }

  async #save(value) {
    if (!this.uuidValue) return

    const normalizedValue = value ?? ""

    // Skip if nothing changed since last save.
    // Treat null (never saved) vs "" (saved as empty) as different so the very
    // first save of an empty field after a non-empty draft is cleared correctly.
    if (this._lastSaved !== null && this._lastSaved === normalizedValue) return

    // Skip empty→empty on first save (no draft existed, nothing to clear).
    if (this._lastSaved === null && normalizedValue === "") return

    // Skip bare trigger chars — a lone "/" or "#" is not a meaningful draft.
    if (normalizedValue.trim() === "/" || normalizedValue.trim() === "#") return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const resp = await fetch(`/chat/${this.uuidValue}`, {
        method: "PATCH",
        headers: {
          "Content-Type":  "application/json",
          "Accept":        "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        },
        body: JSON.stringify({ draft: normalizedValue }),
      })

      if (resp.ok || resp.status === 204) {
        this._lastSaved = normalizedValue
      }
    } catch (err) {
      // Network error — ignore; the next keystroke will retry.
      console.warn("[pito--draft] PATCH failed:", err)
    }
  }
}
