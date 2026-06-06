// pito--games-nav
//
// Mounted on the `.flex.flex-col[data-controller="pito--games-nav"]` element
// that the games picker sidebar injects into #pito-sidebar.
//
// Keyboard (listens on document):
//   ↑ / ↓  — move highlight through .pito-game-row elements
//   Enter  — select: build the right command, populate the chatbox, and submit
//   Escape — handled by pito--resume (clears #pito-sidebar → disconnects us)
//
// Mouse:
//   click .pito-game-row — highlight that row
//
// Mode (from data-pito--games-nav-mode-value):
//   "show"   → fills `show game <id>` in the chatbox + submits
//   "delete" → fills `rm game <id>` in the chatbox + submits
//
// Coexistence with pito--resume:
//   resume's #onKey skips early when rows = [] (no .pito-conversation-row),
//   so it won't fight our arrows.  resume's capture-Esc clears #pito-sidebar,
//   which disconnects this controller — correct.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

const HIGHLIGHT_CLASS = "pito-resume-highlight"

export default class extends Controller {
  static values = {
    mode: { type: String, default: "show" },
  }

  connect() {
    this.abort = new AbortController()
    const sig = { signal: this.abort.signal }

    // Initialise highlight to the first row.
    const rows = this.#rows()
    this.highlightIndex = rows.length ? 0 : -1
    this.#paint(rows)

    document.addEventListener("keydown", this.#onKey.bind(this), sig)
    this.element.addEventListener("click", this.#onClick.bind(this), sig)
  }

  disconnect() {
    this.abort?.abort()
  }

  // ── Test shim ──────────────────────────────────────────────────────────────
  // Exposes #select as a public method for unit tests (private class fields are
  // not accessible via dot notation in the test harness).
  _testSelect(row) { this.#select(row) }

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-game-row"))
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
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
      const row = rows[this.highlightIndex]
      if (row) this.#select(row)
    }
    // Escape is handled by pito--resume's capture-phase listener.
  }

  #onClick(e) {
    const row = e.target.closest(".pito-game-row")
    if (!row) return
    const rows = this.#rows()
    const idx  = rows.indexOf(row)
    if (idx === -1) return
    this.highlightIndex = idx
    this.#paint(rows)
  }

  #move(rows, delta) {
    if (this.highlightIndex === -1) {
      this.highlightIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      this.highlightIndex = Math.max(0, Math.min(rows.length - 1, this.highlightIndex + delta))
    }
    this.#paint(rows)
    // scrollIntoView is not available in all test environments; guard defensively.
    const focused = rows[this.highlightIndex]
    if (focused && typeof focused.scrollIntoView === "function") {
      focused.scrollIntoView({ block: "nearest" })
    }
  }

  #select(row) {
    const gameId = row.dataset.gameId
    if (!gameId) return

    const verb    = this.modeValue === "delete" ? "rm" : "show"
    const command = `${verb} game #${gameId}`

    // Dispatch a custom event that chat_form_controller listens for.
    // The event carries the command to populate + submit.
    document.dispatchEvent(new CustomEvent("pito:picker:select", {
      bubbles: false,
      detail:  { command },
    }))

    // Clear the sidebar (mirror pito--resume #clear).
    const sidebar = document.getElementById("pito-sidebar")
    if (sidebar) sidebar.innerHTML = ""
  }
}
