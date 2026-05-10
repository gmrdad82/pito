import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish — global IGDB-search modal.
//
// Dialog rendered once in `app/views/layouts/application.html.erb`
// (`shared/_igdb_search_modal`). Opened by the `i` keypress (handled
// in `keyboard_controller.js#openIgdbSearch`) and by the `[+]` link
// on `/games`. Submits a debounced query to `GET /games/search` and
// loads the results inside the modal's Turbo Frame
// (`<turbo-frame id="igdb_search_results">`).
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["input"]
  static values = { url: String, debounce: { type: Number, default: 300 } }

  connect() {
    this._timer = null
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer)
  }

  open(event) {
    if (event) event.preventDefault()
    if (typeof this.element.showModal === "function") {
      this.element.showModal()
    }
    if (this.hasInputTarget) {
      setTimeout(() => this.inputTarget.focus(), 0)
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (typeof this.element.close === "function" && this.element.open) {
      this.element.close()
    }
  }

  clickOutside(event) {
    if (event.target === this.element) {
      this.element.close()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      if (this.element.open) this.element.close()
    }
  }

  search() {
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fire(), this.debounceValue)
  }

  submit(event) {
    if (event) event.preventDefault()
    if (this._timer) clearTimeout(this._timer)
    this._fire()
  }

  _fire() {
    if (!this.hasInputTarget) return
    const q = (this.inputTarget.value || "").trim()
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)

    const frame = document.getElementById("igdb_search_results")
    if (!frame) return
    frame.src = url.toString()
  }
}
