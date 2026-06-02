// pito--expand
//
// Generic collapsible content: Ctrl+O toggles the LAST expandable element in
// the DOM (expand ↔ collapse). Works for error details and /help overflow.
//
// Required targets:
//   detail     — the hidden/shown content block
//   hint       — the "ctrl+o …" wrapper line (hidden while expanded)
//   hintLabel  — the text span whose content switches between expand/collapse labels
//
// Values (set by server template):
//   expandLabelValue   — e.g. "to expand"
//   collapseLabelValue — e.g. "to collapse"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hint", "hintLabel", "detail"]
  static values  = { expandLabel: String, collapseLabel: String }

  connect() {
    if (!this.hasDetailTarget) return
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onKeydown.bind(this), { signal: this.abort.signal })
  }

  disconnect() {
    this.abort?.abort()
  }

  // ── internals ──────────────────────────────────────────────────────────────

  get #isExpanded() {
    return this.element.dataset.expanded === "true"
  }

  #toggle() {
    const nowExpanded = !this.#isExpanded
    this.element.dataset.expanded = String(nowExpanded)
    this.detailTarget.classList.toggle("hidden", !nowExpanded)
    if (this.hasHintLabelTarget) {
      this.hintLabelTarget.textContent = nowExpanded
        ? (this.collapseLabel || "to collapse")
        : (this.expandLabel   || "to expand")
    }
  }

  #onKeydown(e) {
    if (!e.ctrlKey || e.key !== "o") return
    if (!this.#isLastExpandable()) return
    e.preventDefault()
    this.#toggle()
  }

  // True only when this is the last element with a detail target in the DOM.
  #isLastExpandable() {
    const all = Array.from(
      document.querySelectorAll('[data-controller~="pito--expand"]')
    ).filter(el => el.querySelector('[data-pito--expand-target="detail"]'))
    return all.at(-1) === this.element
  }
}
