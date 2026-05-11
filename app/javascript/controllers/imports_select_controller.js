// Phase 22 — Imports::Channels selection Stimulus controller.
//
// Drives the channel-pick modal at `/imports/channels`:
//
//   * keeps the `[import N]` submit button disabled until at least
//     one channel checkbox is ticked.
//   * updates the breadcrumb active segment, the modal heading, and
//     the submit button label so each carries the live selection
//     count (`import 2 channels` / `[import 2]` etc).
//   * hides the `[import N]` action entirely when nothing is
//     selected so the toolbar shows only `[cancel]`.
//   * supports a header-row select-all checkbox that toggles every
//     enabled per-row checkbox in one click and reflects the current
//     selection (checked when all are ticked, indeterminate when
//     some are).
//
// The server enforces the same "at least one channel" invariant
// (`POST /imports/channels` with an empty list 422s / redirects), so
// this is a UX layer on top of a hard server check.
//
// NO window.confirm / alert / data-turbo-confirm anywhere in this
// file (CLAUDE.md hard rule).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "checkbox",
    "headerCheckbox",
    "submit",
    "submitLabel",
    "importAction",
    "breadcrumbTitle",
    "headingTitle"
  ]

  connect() {
    this.refresh()
  }

  // Called on per-row checkbox `change`.
  refresh() {
    const count = this.checkboxTargets.filter((cb) => cb.checked).length

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = count === 0
    }

    if (this.hasImportActionTarget) {
      this.importActionTarget.hidden = count === 0
    }

    if (this.hasSubmitLabelTarget) {
      this.submitLabelTarget.textContent = count > 0 ? `import ${count}` : "import"
    }

    const headingCopy = count === 0 ? "import channels" : `import ${count} ${count === 1 ? "channel" : "channels"}`
    if (this.hasBreadcrumbTitleTarget) {
      this.breadcrumbTitleTarget.textContent = `[${headingCopy}]`
    }
    if (this.hasHeadingTitleTarget) {
      this.headingTitleTarget.textContent = headingCopy
    }

    // Sync the header select-all state.
    if (this.hasHeaderCheckboxTarget) {
      const total = this.checkboxTargets.length
      this.headerCheckboxTarget.checked = count > 0 && count === total
      this.headerCheckboxTarget.indeterminate = count > 0 && count < total
    }
  }

  // Called on header-row checkbox `change`. Toggles every enabled
  // per-row checkbox to match the header state, then refreshes the
  // toolbar copy.
  toggleAll() {
    if (!this.hasHeaderCheckboxTarget) return
    const checked = this.headerCheckboxTarget.checked
    this.checkboxTargets.forEach((cb) => {
      if (!cb.disabled) cb.checked = checked
    })
    this.refresh()
  }
}
