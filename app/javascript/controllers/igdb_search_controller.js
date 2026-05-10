import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 — IGDB type-ahead.
//
// Debounced input -> GET /games/search?q=… as a Turbo Frame
// request. The server renders `_search_results.html.erb` inside
// `<turbo-frame id="igdb_search_results">`, which Turbo swaps in
// place. NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["input"]
  static values = { url: String, debounce: { type: Number, default: 300 } }

  connect() {
    this._timer = null
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer)
  }

  search() {
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fire(), this.debounceValue)
  }

  async _fire() {
    const q = (this.inputTarget.value || "").trim()
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)

    const frame = document.getElementById("igdb_search_results")
    if (!frame) return
    frame.src = url.toString()
  }
}
