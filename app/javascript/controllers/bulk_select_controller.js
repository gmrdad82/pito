import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "headerCheckbox", "actions", "count",
                     "bulkCol", "actionCol", "bulkToggle", "openAction", "openHint",
                     "deleteAction"]
  static values = { maxPanes: Number, entityName: String, panesPath: String, deleteType: String }

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

    const ids = this.selectedIds.join(",")

    // update open action — all values are controlled (numeric count, server-set data attributes)
    if (count === 0) {
      this.openHintTarget.hidden = false
      this.openActionTarget.hidden = true
      this._setHint(this.openHintTarget, `select items to act on`)
    } else if (count <= max) {
      this.openHintTarget.hidden = true
      this.openActionTarget.hidden = false
      const panesUrl = `${this.panesPathValue}?ids=${ids}`
      this._setBracketedLink(this.openActionTarget, panesUrl, `open ${count} ${name}`)
    } else {
      this.openHintTarget.hidden = false
      this.openActionTarget.hidden = true
      this._setHint(this.openHintTarget, `max ${max} ${name} at a time`)
    }

    // update delete action — values are numeric IDs and a controlled type string, safe for URL construction
    if (this.hasDeleteActionTarget) {
      if (count > 0) {
        const deleteUrl = `/deletions/${this.deleteTypeValue}/${ids}`
        const link = document.createElement("a")
        link.href = deleteUrl
        link.className = "bracketed text-danger"
        const bracket = document.createTextNode("[ ")
        const span = document.createElement("span")
        span.className = "bl"
        span.textContent = `delete ${count}`
        const bracketEnd = document.createTextNode(" ]")
        link.appendChild(bracket)
        link.appendChild(span)
        link.appendChild(bracketEnd)
        this.deleteActionTarget.replaceChildren(link)
        this.deleteActionTarget.hidden = false
      } else {
        this.deleteActionTarget.hidden = true
      }
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

  _setHint(el, text) {
    const span = document.createElement("span")
    span.className = "text-muted"
    span.textContent = text
    el.replaceChildren(span)
  }

  _setBracketedLink(el, href, label, className = "bracketed") {
    const link = document.createElement("a")
    link.href = href
    link.className = className
    link.appendChild(document.createTextNode("[ "))
    const span = document.createElement("span")
    span.className = "bl"
    span.textContent = label
    link.appendChild(span)
    link.appendChild(document.createTextNode(" ]"))
    el.replaceChildren(link)
  }
}
