import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "headerCheckbox", "actions", "count",
                     "bulkCol", "actionCol", "bulkToggle", "openAction", "openHint",
                     "overMaxHint", "deleteAction", "syncAction"]
  // `maxPanes` and `panesPath` are panes-specific. Screens without an
  // "open in N panes" flow (e.g. /projects) omit the corresponding data
  // attributes on the controller root; defaults below keep the controller
  // safe when the open-related branches are never reached.
  static values = {
    maxPanes: { type: Number, default: 0 },
    entityName: String,
    panesPath: { type: String, default: "" },
    deleteType: String,
    syncType: String
  }

  enterBulk(event) {
    event.preventDefault()
    this.bulkColTargets.forEach(el => el.hidden = false)
    this.actionColTargets.forEach(el => el.hidden = true)
    this.bulkToggleTarget.hidden = true
    this.actionsTarget.hidden = false
    this.updateActions()
    this._updateSeparators()
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
    this._updateSeparators()
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

    // update count display (universal — every bulk-select picker shows it).
    // Use the `_replaceActionContent` shim so the leading `.action-sep`
    // dot stays put — `textContent =` would wipe it.
    this._replaceActionContent(this.countTarget, document.createTextNode(String(count)))

    const ids = this.selectedIds.join(",")

    // update open action — panes-specific. Screens without an "open in N
    // panes" flow (e.g. /projects) omit the openHint / openAction targets
    // entirely; the controller silently skips this branch.
    if (this.hasOpenHintTarget && this.hasOpenActionTarget) {
      if (count === 0) {
        this.openHintTarget.hidden = false
        this.openActionTarget.hidden = true
        this._setHint(this.openHintTarget, `select items to act on`)
      } else if (count <= max) {
        this.openHintTarget.hidden = true
        this.openActionTarget.hidden = false
        const panesUrl = `${this.panesPathValue}?ids=${ids}`
        this._setBracketedLink(this.openActionTarget, panesUrl, `open ${count}`)
      } else {
        // Over max: render [open N] as muted, bold, non-clickable so layout stays
        // stable. The helpful subtext lives below the action bar in the view.
        this.openHintTarget.hidden = true
        this.openActionTarget.hidden = false
        this._setMutedBracketed(this.openActionTarget, `open ${count}`)
      }
    }

    // over-max subtext only appears when selection exceeds max-panes
    if (this.hasOverMaxHintTarget) {
      this.overMaxHintTarget.hidden = count <= max
    }

    // update delete action — values are numeric IDs and a controlled type string, safe for URL construction
    if (this.hasDeleteActionTarget) {
      if (count > 0) {
        const deleteUrl = `/deletions/${this.deleteTypeValue}/${ids}`
        const link = document.createElement("a")
        link.href = deleteUrl
        link.className = "bracketed text-danger"
        const bracket = document.createTextNode("[")
        const span = document.createElement("span")
        span.className = "bl"
        span.textContent = `delete ${count}`
        const bracketEnd = document.createTextNode("]")
        link.appendChild(bracket)
        link.appendChild(span)
        link.appendChild(bracketEnd)
        this._replaceActionContent(this.deleteActionTarget, link)
        this.deleteActionTarget.hidden = false
      } else {
        this.deleteActionTarget.hidden = true
      }
    }

    // update sync action — non-destructive (no text-danger class), same URL shape pattern as delete
    if (this.hasSyncActionTarget) {
      if (count > 0) {
        const syncUrl = `/syncs/${this.syncTypeValue}/${ids}`
        const link = document.createElement("a")
        link.href = syncUrl
        link.className = "bracketed"
        const bracket = document.createTextNode("[")
        const span = document.createElement("span")
        span.className = "bl"
        span.textContent = `sync ${count}`
        const bracketEnd = document.createTextNode("]")
        link.appendChild(bracket)
        link.appendChild(span)
        link.appendChild(bracketEnd)
        this._replaceActionContent(this.syncActionTarget, link)
        this.syncActionTarget.hidden = false
      } else {
        this.syncActionTarget.hidden = true
      }
    }

    // sync header checkbox
    if (this.hasHeaderCheckboxTarget) {
      const total = this.checkboxTargets.length
      this.headerCheckboxTarget.checked = count > 0 && count === total
      this.headerCheckboxTarget.indeterminate = count > 0 && count < total
    }

    // Recompute separator visibility — the leading visible action drops
    // its dot, every subsequent visible action keeps it. Hides the
    // dangling-`·` artefact when the first visible action is, say,
    // `[ cancel ]` with no other action visible alongside it.
    this._updateSeparators()
  }

  get selectedIds() {
    return this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)
  }

  // Internal helper — replace the action-target's content while preserving
  // the leading `.action-sep` (the dot that the bulk-toolbar pattern uses
  // to separate adjacent visible actions). The setter helpers below all
  // route through this so a `replaceChildren` doesn't wipe the separator.
  _replaceActionContent(el, ...nodes) {
    const sep = el.querySelector(".action-sep")
    el.replaceChildren()
    if (sep) el.appendChild(sep)
    nodes.forEach(n => el.appendChild(n))
  }

  _setHint(el, text) {
    const span = document.createElement("span")
    span.className = "text-muted"
    span.textContent = text
    this._replaceActionContent(el, span)
  }

  _setBracketedLink(el, href, label, className = "bracketed") {
    const link = document.createElement("a")
    link.href = href
    link.className = className
    link.appendChild(document.createTextNode("["))
    const span = document.createElement("span")
    span.className = "bl"
    span.textContent = label
    link.appendChild(span)
    link.appendChild(document.createTextNode("]"))
    this._replaceActionContent(el, link)
  }

  // Renders [label] as muted, bold, non-clickable text — used when an action
  // is over its limit (e.g., open N when N exceeds max-panes). Bold preserves
  // visual weight so the bar doesn't shift when toggling between modes.
  _setMutedBracketed(el, label) {
    const span = document.createElement("span")
    span.className = "bracketed-muted"
    span.textContent = `[${label}]`
    this._replaceActionContent(el, span)
  }

  // Toggle `.action-sep` separators so the leading visible action drops
  // its dot. Each `.action` span owns a leading `<span class="action-sep">·</span>`;
  // hiding the action hides its separator (CSS), and we additionally hide
  // the separator on whichever action is currently first-visible to avoid
  // a leading dangling `·`. No-op when the actions toolbar isn't on the
  // page (e.g., the controller wires up but bulk mode hasn't been entered
  // yet on a page that doesn't show the actions container).
  _updateSeparators() {
    if (!this.hasActionsTarget) return
    const visible = this.actionsTarget.querySelectorAll(".action:not([hidden])")
    visible.forEach((el, idx) => {
      const sep = el.querySelector(".action-sep")
      if (sep) sep.hidden = (idx === 0)
    })
  }
}
