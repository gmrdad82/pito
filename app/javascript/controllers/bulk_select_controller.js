import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "headerCheckbox", "actions", "count",
                     "bulkCol", "actionCol", "bulkToggle", "openAction", "openHint",
                     "overMaxHint", "deleteAction", "syncAction", "revokeAction"]
  // Wave 3 Lane J (2026-05-06) — checkboxes are always-on for every
  // bulk-select surface in the app today. The `bulkCol` / `actionCol`
  // / `bulkToggle` / `enterBulk` / `exitBulk` toggle hooks are kept
  // ONLY for the deferred footage bulk-mode follow-up (project SHOW
  // footage pane), which still needs an explicit enter/exit toggle
  // until `Confirmable::TYPES` is extended for footage. Drop these
  // hooks once that follow-up lands. The connect() hook drives the
  // initial action-bar state off zero-selection so [open N] / [sync N]
  // / [delete N] are hidden until the user ticks at least one row.
  // `maxPanes` and `panesPath` are panes-specific. Screens without an
  // "open in N panes" flow (e.g. /projects) omit the corresponding data
  // attributes on the controller root; defaults below keep the controller
  // safe when the open-related branches are never reached.
  static values = {
    maxPanes: { type: Number, default: 0 },
    entityName: String,
    panesPath: { type: String, default: "" },
    deleteType: String,
    syncType: String,
    // Override the verb used on the `[delete N]` action — used by
    // /settings/youtube where the same `/deletions/:type/:ids` framework
    // is the disconnect surface (verb: "disconnect", not "delete").
    // Defaults to "delete" so every existing bulk-select picker keeps
    // its current copy. Mirrors `syncActionLabel` (not currently set
    // by any view but exposed symmetrically so future surfaces can
    // override the sync verb without a controller change).
    deleteActionLabel: { type: String, default: "delete" },
    syncActionLabel: { type: String, default: "sync" },
    // Phase 24 — bulk `[revoke N]` on /channels routes to a dedicated
    // namespace (`/channels/revokes/:ids`) because revoke semantics
    // differ from plain delete (revoke cascades to YoutubeConnection
    // when this channel was the last). `revokePath` defaults to empty;
    // surfaces that opt in (only /channels today) wire the URL prefix.
    revokePath: { type: String, default: "" }
  }

  // Always-on flow: prime the action-bar visibility on connect so
  // [open N] / [sync N] / [delete N] start hidden (count = 0) and the
  // header checkbox reflects the (empty) selection.
  connect() {
    this.updateActions()
  }

  // Legacy entry points retained for any view still wiring `[bulk]` /
  // `[cancel]`. Always-on views drop the wiring entirely; these stay
  // callable so partial migrations don't break.
  enterBulk(event) {
    if (event) event.preventDefault()
    this.bulkColTargets.forEach(el => el.hidden = false)
    this.actionColTargets.forEach(el => el.hidden = true)
    if (this.hasBulkToggleTarget) this.bulkToggleTarget.hidden = true
    if (this.hasActionsTarget) this.actionsTarget.hidden = false
    this.updateActions()
    this._updateSeparators()
  }

  exitBulk(event) {
    if (event) event.preventDefault()
    this.bulkColTargets.forEach(el => el.hidden = true)
    this.actionColTargets.forEach(el => el.hidden = false)
    if (this.hasBulkToggleTarget) this.bulkToggleTarget.hidden = false
    if (this.hasActionsTarget) this.actionsTarget.hidden = true
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
        // 2026-05-11 — the "select items to act on" hint was removed
        // app-wide; the bulk-select checkbox column is self-evident.
        // Keep openHint hidden + empty when no selection.
        this.openHintTarget.hidden = true
        this.openActionTarget.hidden = true
        this._replaceActionContent(this.openHintTarget)
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
        span.textContent = `${this.deleteActionLabelValue} ${count}`
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

    // Phase 24 — update revoke action. Same shape as delete but
    // routes to `/channels/revokes/:ids` (or whatever path the view
    // configured via `data-bulk-select-revoke-path-value`). Renders
    // [revoke N] in red (destructive). Hidden when revokePath is not
    // configured for the surface (e.g. /videos, /projects).
    if (this.hasRevokeActionTarget) {
      if (count > 0 && this.revokePathValue.length > 0) {
        const revokeUrl = `${this.revokePathValue}/${ids}`
        const link = document.createElement("a")
        link.href = revokeUrl
        link.className = "bracketed text-danger"
        const bracket = document.createTextNode("[")
        const span = document.createElement("span")
        span.className = "bl"
        span.textContent = `revoke ${count}`
        const bracketEnd = document.createTextNode("]")
        link.appendChild(bracket)
        link.appendChild(span)
        link.appendChild(bracketEnd)
        this._replaceActionContent(this.revokeActionTarget, link)
        this.revokeActionTarget.hidden = false
      } else {
        this.revokeActionTarget.hidden = true
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
        span.textContent = `${this.syncActionLabelValue} ${count}`
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
