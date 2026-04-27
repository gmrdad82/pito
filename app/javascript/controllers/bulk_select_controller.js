import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "headerCheckbox", "actions", "count",
                     "bulkCol", "actionCol", "bulkToggle", "openAction", "openHint"]
  static values = { maxPanes: Number, entityName: String }

  enterBulk(event) {
    event.preventDefault()
    this.bulkColTargets.forEach(el => el.hidden = false)
    this.actionColTargets.forEach(el => el.hidden = true)
    this.bulkToggleTarget.hidden = true
    this.actionsTarget.hidden = false
    this.updateActions()
  }

  exitBulk(event) {
    event.preventDefault()
    this.bulkColTargets.forEach(el => el.hidden = true)
    this.actionColTargets.forEach(el => el.hidden = false)
    this.bulkToggleTarget.hidden = false
    this.actionsTarget.hidden = true
    this.checkboxTargets.forEach(cb => cb.checked = false)
    if (this.hasHeaderCheckboxTarget) {
      this.headerCheckboxTarget.checked = false
      this.headerCheckboxTarget.indeterminate = false
    }
  }

  toggle() {
    this.updateActions()
  }

  toggleAll() {
    const checked = this.headerCheckboxTarget.checked
    this.checkboxTargets.forEach(cb => cb.checked = checked)
    this.updateActions()
  }

  updateActions() {
    const count = this.selectedIds.length
    const max = this.maxPanesValue
    const name = this.entityNameValue

    // update count display
    this.countTarget.textContent = count

    // update open action
    if (count === 0) {
      this.openHintTarget.hidden = false
      this.openActionTarget.hidden = true
      this.openHintTarget.innerHTML = `<span class="text-muted">you can open up to ${max} ${name} in a split view</span>`
    } else if (count <= max) {
      this.openHintTarget.hidden = true
      this.openActionTarget.hidden = false
      this.openActionTarget.innerHTML = `<a href="#" class="bracketed">[ <span class="bl">open ${count} ${name}</span> ]</a>`
    } else {
      this.openHintTarget.hidden = false
      this.openActionTarget.hidden = true
      this.openHintTarget.innerHTML = `<span class="text-muted">max ${max} ${name} at a time</span>`
    }

    // sync header checkbox
    if (this.hasHeaderCheckboxTarget) {
      const total = this.checkboxTargets.length
      this.headerCheckboxTarget.checked = count > 0 && count === total
      this.headerCheckboxTarget.indeterminate = count > 0 && count < total
    }
  }

  get selectedIds() {
    return this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)
  }
}
