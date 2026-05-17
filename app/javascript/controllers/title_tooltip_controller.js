import { Controller } from "@hotwired/stimulus"

// 2026-05-17 — "tooltip only when truncated" for game-tile titles.
//
// The game tile renders the title in a single line with CSS ellipsis
// truncation (`white-space: nowrap; overflow: hidden; text-overflow:
// ellipsis`). A blanket `title=` attribute would surface the hover
// tooltip on every tile, including short titles where the rendered
// text already shows the whole string — visually noisy and unhelpful.
//
// This controller measures the element after each layout pass and
// sets/removes the native `title` attribute based on whether the
// rendered text is actually clipped (`scrollWidth > clientWidth`):
//
//   * truncated  → `title` is set to the full title string.
//   * not truncated → `title` is removed (no hover tooltip).
//
// A `ResizeObserver` re-runs the check whenever the tile's caption
// box changes size (responsive grid reflows, parent container width
// change, etc.) so the tooltip stays accurate after layout shifts.
export default class extends Controller {
  static values = { fullTitle: String }

  connect() {
    this.updateTooltip()
    this.observer = new ResizeObserver(() => this.updateTooltip())
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
  }

  updateTooltip() {
    const truncated = this.element.scrollWidth > this.element.clientWidth
    if (truncated) {
      this.element.setAttribute("title", this.fullTitleValue)
    } else {
      this.element.removeAttribute("title")
    }
  }
}
