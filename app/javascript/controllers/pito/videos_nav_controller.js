// pito--videos-nav
//
// Mounted on the `.flex.flex-col[data-controller="pito--videos-nav"]` element
// that the videos picker sidebar injects into #pito-sidebar.
//
// Keyboard (listens on document):
//   ↑ / ↓  — move highlight through .pito-video-row elements
//   Enter  — select: fill `show vid <id>` in the chatbox and submit
//   Escape — handled by pito--resume (clears #pito-sidebar → disconnects us)
//
// Mouse:
//   click .pito-video-row — highlight that row
//
// Search (optional — only when input/list targets are present):
//   input target — <input> element; typing debounces a POST /videos/search-local
//   list  target — container whose innerHTML is replaced with new row HTML
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { paletteOpen } from "pito/settings"

const HIGHLIGHT_CLASS = "pito-resume-highlight"
const DEBOUNCE_MS = 250

export default class extends Controller {
  static targets = ["input", "list", "shimmer"]

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
  _testSelect(row) { this.#select(row) }

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    const container = this.hasListTarget ? this.listTarget : this.element
    return Array.from(container.querySelectorAll(".pito-video-row"))
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
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
      if (row) this.#select(row)
    }
    // Escape is handled by pito--resume's capture-phase listener.
  }

  #onClick(e) {
    const row = e.target.closest(".pito-video-row")
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
    const focused = rows[this.highlightIndex]
    if (focused && typeof focused.scrollIntoView === "function") {
      focused.scrollIntoView({ block: "nearest" })
    }
  }

  #select(row) {
    const videoId = row.dataset.videoId
    if (!videoId) return

    const command = `show vid #${videoId}`

    document.dispatchEvent(new CustomEvent("pito:picker:select", {
      bubbles: false,
      detail:  { command },
    }))

    const sidebar = document.getElementById("pito-sidebar")
    if (sidebar) sidebar.innerHTML = ""
  }

  // ── Search (debounced POST /videos/search-local) ───────────────────────────

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
      const resp = await fetch("/videos/search-local", {
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
