// pito--rename
//
// Mounted on each conversation row in the sidebar list.
// Provides inline rename: double-click the name label — or press "n" while the
// row is highlighted (pito--resume dispatches "pito:rename:start") — to replace
// it with an <input>. Enter / blur submit a PATCH to /chat/:uuid with
// { title: <new value> }. Escape cancels without saving.
//
// Values:
//   url  — the PATCH endpoint, e.g. "/chat/<uuid>" (required)
//
// DOM contract (from conversations/_row.html.erb):
//   - The display name lives in a <span class="pito--rename-display"> child.
//   - The row keeps class "pito-conversation-row", data-conversation-uuid, and
//     all other attributes that pito--resume and pito--sidebar depend on.
//
// Turbo Stream response: the server replaces the row element entirely via
//   turbo_stream.replace("conversation_row_<uuid>", ...)
// which Turbo handles automatically — no extra JS needed after the fetch.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this._onDblClick    = this.#startRename.bind(this)
    this._onRenameStart = this.#startRename.bind(this)
    this.element.addEventListener("dblclick", this._onDblClick)
    // Dispatched by pito--resume when "n" is pressed on the highlighted row.
    this.element.addEventListener("pito:rename:start", this._onRenameStart)
  }

  disconnect() {
    this.element.removeEventListener("dblclick", this._onDblClick)
    this.element.removeEventListener("pito:rename:start", this._onRenameStart)
    this.#cancelRename()
  }

  // ── Private ────────────────────────────────────────────────────────────────

  get #displaySpan() {
    return this.element.querySelector(".pito--rename-display")
  }

  #startRename(e) {
    // Don't open a second input if one is already open.
    if (this.element.querySelector("input.pito--rename-input")) return

    e.stopPropagation() // prevent pito--resume from treating this as navigation

    const span = this.#displaySpan
    if (!span) return

    const currentTitle = span.textContent.trim()

    // Build the input — borderless/transparent; the orange underline is drawn
    // on the whole row via .pito-row-editing (see application.css). Uses the
    // browser's normal native caret — no JS overlay, nothing to tear down.
    const input = document.createElement("input")
    input.type      = "text"
    input.value     = currentTitle
    input.className = "pito--rename-input text-fg bg-transparent outline-none w-full"

    // Grow the name so the input + row underline span the full width, and flag
    // the row as editing (drops the highlight bg, draws the orange underline).
    span.classList.add("flex-1", "min-w-0")
    this.element.classList.add("pito-row-editing")

    // Replace span content with the input
    span.textContent = ""
    span.appendChild(input)
    input.focus()
    input.select()

    // Commit on blur (unless we're already committing via Enter)
    input.addEventListener("blur", () => { this.#commitRename(input) }, { once: true })

    input.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") {
        ev.preventDefault()
        ev.stopImmediatePropagation()
        // Remove blur listener before we manually commit so it doesn't fire twice.
        input.blur()
      } else if (ev.key === "Escape") {
        ev.preventDefault()
        ev.stopImmediatePropagation()
        this.#cancelRename(input, currentTitle)
      } else {
        // Prevent resume-controller arrow/enter navigation while typing
        ev.stopPropagation()
      }
    })
  }

  // Restore the row to its non-editing visual state (drops the grow/underline).
  #endEditing() {
    this.element.classList.remove("pito-row-editing")
    this.#displaySpan?.classList.remove("flex-1", "min-w-0")
  }

  #cancelRename(input, restoreTitle) {
    if (!input) {
      input = this.element.querySelector("input.pito--rename-input")
      if (!input) return
    }
    const span = this.#displaySpan
    if (span) {
      span.textContent = restoreTitle ?? span.textContent
      // Remove the input if it's still there (cancel via Escape).
      const orphan = span.querySelector("input.pito--rename-input")
      if (orphan) orphan.remove()
    }
    this.#endEditing()
  }

  async #commitRename(input) {
    const span     = this.#displaySpan
    const newTitle = input.value.trim()

    if (!newTitle) {
      // Blank — restore original text and bail without a network call.
      if (span) span.textContent = input.dataset.originalTitle || input.defaultValue
      this.#endEditing()
      return
    }

    // Optimistically update the display while we wait.
    if (span) span.textContent = newTitle

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const resp = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type":  "application/json",
          "Accept":        "text/vnd.turbo-stream.html, application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        },
        body: JSON.stringify({ title: newTitle }),
      })

      if (!resp.ok) {
        // Server rejected (e.g. 422) — leave the optimistic text in place
        // or restore from the response. Simple: just keep what's shown.
        console.warn("[pito--rename] PATCH failed:", resp.status)
        return
      }

      const contentType = resp.headers.get("content-type") || ""
      if (contentType.includes("turbo-stream")) {
        const html = await resp.text()
        // Let Turbo process the stream — it will replace the row DOM element,
        // at which point this controller instance will be disconnected.
        Turbo.renderStreamMessage(html)
      }
    } catch (err) {
      console.warn("[pito--rename] PATCH error:", err)
    }
  }
}
