import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish — global IGDB-search modal.
//
// Dialog rendered once in `app/views/layouts/application.html.erb`
// (`shared/_igdb_search_modal`). Opened by the `[+]` bracketed link
// in the `/games` chrome (2026-05-17 the global `i` keybind was
// removed in the legacy-keyboard-shortcut sweep — the modal is now
// reachable only via the `[+]` link). Submits a debounced query to
// `GET /games/search` and loads the results inside the modal's Turbo
// Frame (`<turbo-frame id="igdb_search_results">`).
//
// Phase 27 spec 04 (2026-05-17) — auto-search behavior:
//   - The input fires `#search` automatically when the trimmed
//     value's length is ≥ `minCharsValue` (default 5), debounced
//     `debounceValue` ms (default 250).
//   - Pressing Enter at any length ≥ 1 fires `#search` immediately,
//     bypassing the min-chars guard (lets users explicitly search
//     short terms like `"DOOM"`).
//   - The explicit `[search]` button (and its `submit` action) are
//     gone. The `_fire` path is the only entry point.
//   - Backspacing below the min-chars cutoff does NOT clear the
//     results frame — the prior successful render stays put.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["input"]
  static values = {
    url: String,
    debounce: { type: Number, default: 250 },
    minChars: { type: Number, default: 5 }
  }

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

  // `input` event handler AND `keydown.enter` handler. Enter bypasses
  // the min-chars guard and fires immediately; an `input` event with
  // a trimmed value below the cutoff is dropped silently.
  search(event) {
    if (!this.hasInputTarget) return
    const q = (this.inputTarget.value || "").trim()
    const isEnter = event && event.type === "keydown" && event.key === "Enter"

    if (isEnter) {
      if (event) event.preventDefault()
      if (q.length === 0) return
      if (this._timer) clearTimeout(this._timer)
      this._fire(q)
      return
    }

    if (q.length < this.minCharsValue) return

    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fire(q), this.debounceValue)
  }

  _fire(q) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)

    const frame = document.getElementById("igdb_search_results")
    if (!frame) return
    frame.src = url.toString()
  }
}
