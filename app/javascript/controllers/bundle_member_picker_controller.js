import { Controller } from "@hotwired/stimulus"

// Phase 14 §2 — Bundle member picker.
//
// Filters the `<select>` of available games (rendered server-side
// from the local Game library — master-agent decision #4) by a
// case-insensitive substring match on the search input. NOT an
// IGDB live search; the bundle is curated from games the user
// already owns (Spec 01's add-game flow handles new IGDB games
// before they show up in the picker here).
//
// Surfaces a `[no games match]` empty caption when no option's
// label contains the search term. NO `confirm()` / `alert()`
// (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["input", "select", "empty"]

  connect() {
    this._allOptions = Array.from(this.selectTarget.options).slice() // includes prompt
  }

  filter() {
    const term = (this.inputTarget.value || "").trim().toLowerCase()
    let matches = 0

    // First option is the prompt; keep it visible.
    Array.from(this.selectTarget.options).forEach((opt, i) => {
      if (i === 0) return
      const label = (opt.text || "").toLowerCase()
      const visible = term.length === 0 || label.includes(term)
      opt.hidden = !visible
      if (visible) matches += 1
    })

    if (term.length === 0) {
      this.emptyTarget.hidden = true
      return
    }
    this.emptyTarget.hidden = matches > 0
  }
}
