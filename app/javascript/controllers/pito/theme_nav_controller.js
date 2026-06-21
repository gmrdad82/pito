// pito--theme-nav
//
// Mounted on the `.flex.flex-col[data-controller="pito--theme-nav"]` element
// that the themes sidebar injects into #pito-sidebar.
//
// Keyboard (listens on document, like pito--notifications-nav):
//   ↑ / ↓   — move highlight through .pito-theme-row elements
//             + live-preview: sets document.documentElement.dataset.theme
//   Enter   — apply: PATCH /settings/theme {theme:slug} + clear sidebar
//   Escape  — handled by pito--resume (clears #pito-sidebar → disconnects us)
//
// Mouse:
//   click .pito-theme-row — highlight that row + live-preview its theme
//
// Revert on dismiss:
//   disconnect() fires when Esc clears #pito-sidebar (pito--resume) or on any
//   navigation.  If Enter was never pressed we revert data-theme to the
//   persisted originalTheme.  An AbortController cleans up all listeners.
//
// Coexistence with pito--resume:
//   resume's #onKey skips early when rows = [] (no .pito-conversation-row),
//   so it won't fight our arrows.  resume's capture-Esc clears #pito-sidebar,
//   which disconnects this controller, which reverts the preview — correct.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { currentTheme, paletteOpen } from "pito/settings"

const HIGHLIGHT_CLASS = "pito-resume-highlight"

export default class extends Controller {
  connect() {
    this.abort = new AbortController()
    const sig = { signal: this.abort.signal }

    // Record the persisted theme so we can revert to it on dismiss.
    this.originalTheme = currentTheme()
    this.applied = false

    // Initialise highlight to the is-current row, or the first row.
    const rows = this.#rows()
    const currentIndex = rows.findIndex((r) => r.classList.contains("is-current"))
    this.highlightIndex = currentIndex >= 0 ? currentIndex : (rows.length ? 0 : -1)
    this.#paint(rows)

    // Apply the highlighted row's theme immediately (so the current theme is
    // visible in the preview even before the user presses any key).
    this.#previewHighlighted(rows)

    document.addEventListener("keydown", this.#onKey.bind(this), sig)
    this.element.addEventListener("click", this.#onClick.bind(this), sig)
  }

  disconnect() {
    this.abort?.abort()

    // Revert the live preview if the user dismissed without applying.
    if (!this.applied) {
      document.documentElement.dataset.theme = this.originalTheme
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-theme-row"))
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
  }

  #previewHighlighted(rows) {
    const row = rows[this.highlightIndex]
    if (row) document.documentElement.dataset.theme = row.dataset.themeName
  }

  #onKey(e) {
    if (paletteOpen()) return // command palette owns the keys while open

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
      const row = rows[this.highlightIndex]
      if (row) this.#apply(row.dataset.themeName)
    }
    // Escape is handled by pito--resume's capture-phase listener.
  }

  #onClick(e) {
    const row = e.target.closest(".pito-theme-row")
    if (!row) return
    const rows = this.#rows()
    const idx = rows.indexOf(row)
    if (idx === -1) return
    this.highlightIndex = idx
    this.#paint(rows)
    this.#previewHighlighted(rows)
  }

  #move(rows, delta) {
    if (this.highlightIndex === -1) {
      this.highlightIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      this.highlightIndex = Math.max(0, Math.min(rows.length - 1, this.highlightIndex + delta))
    }
    this.#paint(rows)
    this.#previewHighlighted(rows)
    rows[this.highlightIndex]?.scrollIntoView({ block: "nearest" })
  }

  #apply(slug) {
    if (!slug) return

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    fetch("/settings/theme", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(csrf ? { "X-CSRF-Token": csrf } : {}),
      },
      body: JSON.stringify({ theme: slug }),
    }).catch((err) => console.warn("[pito--theme-nav] apply failed:", err))

    this.applied = true
    this.originalTheme = slug

    // Clear the sidebar (mirror pito--resume #clear).
    // Finding the sidebar element via the DOM: our element is inside #pito-sidebar.
    const sidebar = document.getElementById("pito-sidebar")
    if (sidebar) sidebar.innerHTML = ""
  }
}
