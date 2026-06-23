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
//   click .pito-game-row — highlight that row AND select it (= arrow-to-it + Enter)
//
// Mode (from data-pito--games-nav-mode-value):
//   "show"   → fills `show game <id>` in the chatbox + submits
//   "delete" → fills `rm game <id>` in the chatbox + submits
//
// Search (optional — only when input/list targets are present):
//   input target — <input> element; typing debounces a POST /games/search-local
//   list  target — container whose innerHTML is replaced with new row HTML
//
// Coexistence with pito--resume:
//   resume's #onKey skips early when rows = [] (no .pito-conversation-row),
//   so it won't fight our arrows.  resume's capture-Esc clears #pito-sidebar,
//   which disconnects this controller — correct.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { paletteOpen } from "pito/settings"

const HIGHLIGHT_CLASS = "pito-resume-highlight"
const DEBOUNCE_MS = 250

export default class extends Controller {
  static targets = ["input", "list", "shimmer"]
  static values = {
    mode: { type: String, default: "show" },
  }

  connect() {
    this.abort = new AbortController()
    const sig = { signal: this.abort.signal }

    this._searchTimer = null
    this._searchAbort = null
    this._searchRequestId = 0

    // Initialise highlight to the first row.
    const rows = this.#rows()
    this.highlightIndex = rows.length ? 0 : -1
    this.#paint(rows)

    document.addEventListener("keydown", this.#onKey.bind(this), sig)
    this.element.addEventListener("click", this.#onClick.bind(this), sig)

    // Wire search input if present.
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("input", this.#onInput.bind(this), sig)
      requestAnimationFrame(() => this.inputTarget.focus())
    }
  }

  disconnect() {
    this.abort?.abort()
    this.#cancelSearch()
  }

  // ── Test shim ──────────────────────────────────────────────────────────────
  // Exposes #select as a public method for unit tests (private class fields are
  // not accessible via dot notation in the test harness).
  _testSelect(row) { this.#select(row) }

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    const container = this.hasListTarget ? this.listTarget : this.element
    return Array.from(container.querySelectorAll(".pito-game-row"))
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
  }

  #onKey(e) {
    if (paletteOpen()) return // command palette owns the keys while open

    // Don't hijack keys while focus is in a text field OUTSIDE the picker (the
    // chatbox). Otherwise Enter-to-send gets stolen and the highlighted game is
    // injected as `show/rm game #id`, clobbering whatever you were typing. The
    // picker's own search input lives inside this.element, so it's unaffected.
    const active = document.activeElement
    if (active && !this.element.contains(active) &&
        (active.tagName === "TEXTAREA" || active.tagName === "INPUT")) {
      return
    }

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
    // Click == arrow-to-it + Enter: highlight the row, then run the same select path.
    this.highlightIndex = idx
    this.#paint(rows)
    this.#select(row)
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

  // ── Search (debounced POST /games/search-local) ────────────────────────────

  #onInput() {
    this.#cancelSearch()
    const q = this.inputTarget.value.trim()
    this._searchTimer = setTimeout(() => {
      this._searchTimer = null
      this.#doSearch(q)
    }, DEBOUNCE_MS)
  }

  async #doSearch(query) {
    this.#cancelSearch()
    this.#showShimmer()
    const myId = ++this._searchRequestId
    const abort = new AbortController()
    this._searchAbort = abort

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const resp = await fetch("/games/search-local", {
        method:  "POST",
        signal:  abort.signal,
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept":       "text/html, */*",
          ...(csrf ? { "X-CSRF-Token": csrf } : {}),
        },
        body: new URLSearchParams({ q: query }),
      })

      if (myId !== this._searchRequestId) return

      this.#hideShimmer()
      if (!resp.ok) return

      const html = await resp.text()
      if (myId !== this._searchRequestId) return

      const container = this.hasListTarget ? this.listTarget : this.element
      container.innerHTML = html

      // Re-pin highlight to the first row of the fresh results.
      const rows = this.#rows()
      this.highlightIndex = rows.length ? 0 : -1
      this.#paint(rows)
    } catch (err) {
      if (err.name !== "AbortError") {
        this.#hideShimmer()
        // Non-critical: swallow network errors; the existing list remains visible.
      }
    }
  }

  #showShimmer() {
    if (this.hasShimmerTarget) this.shimmerTarget.classList.remove("hidden")
  }

  #hideShimmer() {
    if (this.hasShimmerTarget) this.shimmerTarget.classList.add("hidden")
  }

  #cancelSearch() {
    if (this._searchTimer !== null) {
      clearTimeout(this._searchTimer)
      this._searchTimer = null
    }
    if (this._searchAbort) {
      this._searchAbort.abort()
      this._searchAbort = null
    }
    this._searchRequestId++
  }
}
