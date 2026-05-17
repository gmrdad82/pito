import { Controller } from "@hotwired/stimulus"

// 2026-05-18 — shared omnisearch modal controller.
//
// Backs the `shared/_omnisearch_modal` partial. Mode-agnostic — it
// only knows about a debounced query → Turbo Frame swap. The
// per-mode results partial (rendered server-side by
// `_omnisearch_results`) decides how to display rows and what
// per-row actions render.
//
// Values:
//   url        — string. Backend endpoint that returns the results
//                partial wrapped in a Turbo Frame whose id matches
//                `frameIdValue`.
//   debounce   — number, ms. Default 250.
//   minChars   — number, default 1. Lengths below this skip the
//                request silently (avoids an empty-query round-trip
//                on the first keystroke clearing).
//   frameId    — string. DOM id of the `<turbo-frame>` inside the
//                modal that result partials wrap their output in.
//
// Targets:
//   input      — the `<input type="search">` element.
//
// NO `confirm()` / `alert()` / `prompt()` — CLAUDE.md hard rule.
export default class extends Controller {
  static targets = ["input"]
  static values = {
    url: String,
    debounce: { type: Number, default: 250 },
    minChars: { type: Number, default: 1 },
    frameId: String
  }

  connect() {
    this._timer = null
  }

  disconnect() {
    if (this._timer) clearTimeout(this._timer)
  }

  open(event) {
    if (event) event.preventDefault()
    if (typeof this.element.showModal === "function" && !this.element.open) {
      this.element.showModal()
    }
    if (this.hasInputTarget) {
      // Pre-select existing text so a repeat open replaces rather than
      // appends. setTimeout 0 defers until after the dialog promotion
      // hands focus around.
      setTimeout(() => {
        this.inputTarget.focus()
        this.inputTarget.select()
      }, 0)
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

    const frameId = this.frameIdValue
    if (!frameId) return
    const frame = document.getElementById(frameId)
    if (!frame) return
    frame.src = url.toString()
  }
}
