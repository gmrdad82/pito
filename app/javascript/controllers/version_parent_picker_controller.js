import { Controller } from "@hotwired/stimulus"

// Phase 28 §01a — version-parent typeahead picker.
//
// Type into the input, fetch primaries via
// `GET /games/version_parent_search?q=...`, render `{id, title}` rows
// in a dropdown, click a row to populate the hidden id. `[detach]`
// clears the hidden value back to "" so form submit sets
// `version_parent_id` to nil on the server.
//
// CLAUDE.md hard rule: no `confirm()` / `alert()` / `prompt()`.
export default class extends Controller {
  static targets = ["input", "hiddenId", "results", "detachLink"]
  static values = {
    searchUrl: String,
    selfId: String,
    debounceMs: { type: Number, default: 150 }
  }

  connect() {
    this._timer = null
    this._lastQuery = ""
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer)
  }

  search() {
    const term = (this.inputTarget.value || "").trim()
    if (term.length === 0) {
      this._hideResults()
      return
    }
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetchAndRender(term), this.debounceMsValue)
  }

  keydown(event) {
    // Enter inside the input must NOT submit the form mid-search.
    if (event.key === "Enter") {
      event.preventDefault()
    }
    if (event.key === "Escape") {
      this._hideResults()
    }
  }

  detach(event) {
    event.preventDefault()
    this.hiddenIdTarget.value = ""
    this.inputTarget.value = ""
    this._hideResults()
    if (this.hasDetachLinkTarget) {
      this.detachLinkTarget.style.display = "none"
    }
  }

  async _fetchAndRender(term) {
    if (term === this._lastQuery) return
    this._lastQuery = term

    const url = new URL(this.searchUrlValue, window.location.origin)
    url.searchParams.set("q", term)
    if (this.selfIdValue) {
      url.searchParams.set("exclude_id", this.selfIdValue)
    }

    try {
      const response = await fetch(url.toString(), {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) {
        this._hideResults()
        return
      }
      const payload = await response.json()
      const results = Array.isArray(payload.results) ? payload.results : []
      this._renderResults(results)
    } catch (_err) {
      this._hideResults()
    }
  }

  _renderResults(rows) {
    const list = this.resultsTarget
    this._clearChildren(list)
    if (rows.length === 0) {
      const li = document.createElement("li")
      li.className = "text-muted"
      li.style.padding = "4px 8px"
      li.textContent = "no matches."
      list.appendChild(li)
      list.style.display = "block"
      return
    }
    rows.forEach(row => {
      const li = document.createElement("li")
      li.className = "version-parent-picker-result"
      li.style.padding = "4px 8px"
      li.style.cursor = "pointer"
      li.dataset.id = String(row.id)
      // `textContent` only — never innerHTML — so server-side titles
      // cannot inject markup (defence in depth; titles are already
      // ActiveSupport-safe on the Ruby side).
      li.textContent = row.title
      li.addEventListener("click", () => this._pick(row))
      list.appendChild(li)
    })
    list.style.display = "block"
  }

  _pick(row) {
    this.hiddenIdTarget.value = String(row.id)
    this.inputTarget.value = row.title
    this._hideResults()
  }

  _hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.style.display = "none"
      this._clearChildren(this.resultsTarget)
    }
  }

  _clearChildren(node) {
    while (node.firstChild) node.removeChild(node.firstChild)
  }
}
