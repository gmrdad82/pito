import { Controller } from "@hotwired/stimulus"

// Phase 14 §3 — type-ahead picker for the video edit form's [ add link ]
// button. Sources from local `Game` and `Bundle` data already
// rendered in the picker's hidden options — no server round-trips,
// no IGDB calls. Pure UI: filters the option list by case-
// insensitive substring match.
//
// NO `confirm()` / `alert()` / `prompt()`.
export default class extends Controller {
  static targets = ["input", "option", "empty"]

  connect() {
    this.applyFilter()
  }

  filter() {
    this.applyFilter()
  }

  applyFilter() {
    const query = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    let visible = 0

    this.optionTargets.forEach((option) => {
      const haystack = (option.dataset.searchText || option.textContent || "").toLowerCase()
      const match = query === "" || haystack.includes(query)
      option.hidden = !match
      if (match) visible += 1
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible !== 0
    }
  }
}
