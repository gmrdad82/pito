import { Controller } from "@hotwired/stimulus"

// Phase 15 §2 — toggles per-type metadata sub-form fields based on
// the selected entry_type radio. The actual sub-form fields live in
// the form partial as type-tagged sections (`data-type="game_release"`,
// etc.); this controller flips visibility.
//
// Strict no `confirm()` / `alert()` / `prompt()` per CLAUDE.md hard rule.
export default class extends Controller {
  connect() {
    this.updateType()
  }

  updateType() {
    const checked = this.element.querySelector('input[name="calendar_entry[entry_type]"]:checked')
    if (!checked) return
    const type = checked.value
    this.element.querySelectorAll("[data-type]").forEach((section) => {
      section.style.display = section.dataset.type === type ? "" : "none"
    })
  }
}
