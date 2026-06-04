// pito--resume
//
// Mounted on #pito-sidebar. When /resume populates the sidebar via a Turbo Stream
// update, this controller activates keyboard and mouse navigation for the
// conversation list.
//
// Keyboard:
//   ↑ / ↓   — move highlight through rows
//   Enter   — select highlighted row
//   Escape  — clear (empty) the sidebar
//
// Mouse:
//   click .pito-conversation-row — select that row
//
// Selecting a row:
//   - If the row has class "is-current" (already the active conversation) → just clear.
//   - Otherwise → Turbo.visit("/chat/<uuid>").
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const HIGHLIGHT_CLASS = "pito-resume-highlight"

export default class extends Controller {
  connect() {
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onKey.bind(this), { signal: this.abort.signal })
    this.element.addEventListener("click", this.#onClick.bind(this), { signal: this.abort.signal })
    this.highlightIndex = -1

    // The sidebar content is injected via a Turbo Stream UPDATE (this controller
    // stays connected). Watch for it: when rows appear we (a) hide the command
    // dots — /resume is a sync command and never fires pito:done otherwise — and
    // (b) highlight the first row so arrow-nav is immediately visible.
    this.observer = new MutationObserver(() => this.#onContentChange())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.abort?.abort()
    this.observer?.disconnect()
  }

  #onContentChange() {
    const rows = this.#rows()
    if (rows.length && this.highlightIndex === -1) {
      // Sidebar just opened — stop the command dots and highlight the first row.
      document.dispatchEvent(new CustomEvent("pito:done", { bubbles: true }))
      this.highlightIndex = 0
      rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === 0))
    } else if (!rows.length) {
      this.highlightIndex = -1
    }
  }

  // Called by Turbo after the sidebar content is updated so we can initialise
  // the highlight. Turbo fires turbo:render which we listen to globally, but
  // it is simpler to rely on the MutationObserver-based connect/disconnect
  // lifecycle. When the element's children change (Turbo Stream update) the
  // controller is not re-connected, so we re-initialise on every keydown.

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-conversation-row"))
  }

  #onKey(e) {
    const rows = this.#rows()
    if (!rows.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.#move(rows, 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.#move(rows, -1)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const highlighted = rows[this.highlightIndex]
      if (highlighted) this.#select(highlighted)
    } else if (e.key === "Escape") {
      e.preventDefault()
      this.#clear()
    }
  }

  #onClick(e) {
    const row = e.target.closest(".pito-conversation-row")
    if (!row) return
    this.#select(row)
  }

  #move(rows, delta) {
    // Initialise to first/last on first keypress
    if (this.highlightIndex === -1) {
      this.highlightIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      this.highlightIndex = Math.max(0, Math.min(rows.length - 1, this.highlightIndex + delta))
    }
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
    rows[this.highlightIndex]?.scrollIntoView({ block: "nearest" })
  }

  #select(row) {
    const uuid = row.dataset.conversationUuid
    if (!uuid) { this.#clear(); return }

    if (row.classList.contains("is-current")) {
      // Already on this conversation — just close the sidebar.
      this.#clear()
      return
    }

    this.#clear()
    Turbo.visit("/chat/" + uuid)
  }

  #clear() {
    this.element.innerHTML = ""
    this.highlightIndex = -1
  }
}
