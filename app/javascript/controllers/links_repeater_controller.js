import { Controller } from "@hotwired/stimulus"

// Phase 7.5 §11c — Channel edit form. Repeater for the `links` jsonb
// editor. Adds a row on `[+ add link]`, hides a row on `[remove]`
// (soft-delete via the `_destroy=yes` hidden flag — server filters).
//
// Server-side cap of 5 is the authoritative gate (Channel#links_shape
// validator). This controller hides the `[+ add link]` button when
// the visible row count reaches 5 — client-side polish only.
//
// Strict no `confirm()` / `alert()` / `prompt()` per CLAUDE.md hard rule.
// Soft-removal (hide + flag) avoids any confirmation dialog.
export default class extends Controller {
  static targets = ["container", "row", "addContainer", "addButton", "destroyFlag"]
  static values = { max: { type: Number, default: 5 } }

  connect() {
    this.refreshAddVisibility()
  }

  add(event) {
    event.preventDefault()
    if (this.visibleRowCount() >= this.maxValue) {
      this.refreshAddVisibility()
      return
    }

    const template = this.rowTargets[0]
    if (!template) return

    const newRow = template.cloneNode(true)
    const nextIndex = this.rowTargets.length

    // Reindex name attributes so links_attributes[N] is unique per
    // row. The form is submitted as a flat array of indexed entries;
    // gaps in N are fine (server filters destroyed rows).
    newRow.querySelectorAll("input").forEach((input) => {
      if (input.name) {
        input.name = input.name.replace(/\[\d+\]/, `[${nextIndex}]`)
      }
      if (input.type === "hidden") {
        input.value = "no"
      } else {
        input.value = ""
      }
    })

    this.containerTarget.insertBefore(newRow, this.addContainerTarget)
    this.refreshAddVisibility()
  }

  remove(event) {
    event.preventDefault()
    const row = event.currentTarget.closest("[data-links-repeater-target='row']")
    if (!row) return
    const destroyFlag = row.querySelector("[data-links-repeater-target='destroyFlag']")
    if (destroyFlag) destroyFlag.value = "yes"
    row.hidden = true
    this.refreshAddVisibility()
  }

  refreshAddVisibility() {
    if (!this.hasAddContainerTarget) return
    if (this.visibleRowCount() >= this.maxValue) {
      this.addContainerTarget.hidden = true
    } else {
      this.addContainerTarget.hidden = false
    }
  }

  visibleRowCount() {
    return this.rowTargets.filter((row) => !row.hidden).length
  }
}
