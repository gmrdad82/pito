import { Controller } from "@hotwired/stimulus"

// Phase 16 §3 UX restructure 2026-05-10 — dynamic [mark all as read] button.
//
// Watches every `bulk-select` checkbox (lives in the row partial) and
// updates the button label + form action based on selection:
//
//   - 0 selected (default)             -> "[mark all as read]" -> /notifications/mark_all_read
//   - 1 ≤ N < total_unread selected   -> "[mark <N> as read]"  -> /notifications/mark_read?ids=A,B,C
//   - selection == total_unread        -> "[mark all as read]" -> /notifications/mark_all_read
//
// The label span carries `data-notifications-dynamic-button-target="label"`
// and the form carries `data-notifications-dynamic-button-target="form"`.
// `markAllUrlValue` and `markReadUrlValue` are wired from the view.
//
// `totalUnreadValue` is the page's count of currently-unread rows. When all
// unread checkboxes are selected we revert to the canonical "mark all as
// read" label so the button always reflects the most economical action.
export default class extends Controller {
  static targets = ["label", "form"]
  static values = {
    markAllUrl:   String,
    markReadUrl:  String,
    totalUnread:  Number
  }

  connect() {
    this._update = this._update.bind(this)
    // Listen for any checkbox change anywhere on the page — the
    // bulk-select controller mutates checkbox `.checked` directly so
    // this is the most reliable hook.
    document.addEventListener("change", this._update)
    this._update()
  }

  disconnect() {
    document.removeEventListener("change", this._update)
  }

  _update() {
    const selected = this._selectedUnreadIds()
    const count    = selected.length
    const total    = this.totalUnreadValue

    if (count === 0 || (total > 0 && count === total)) {
      // Default / fully-selected — canonical mark-all path.
      this._setLabel("mark all as read")
      this._setFormAction(this.markAllUrlValue)
    } else {
      this._setLabel(`mark ${count} as read`)
      const url = `${this.markReadUrlValue}?ids=${selected.join(",")}`
      this._setFormAction(url)
    }
  }

  // Returns the list of selected ids, restricted to checkboxes whose row
  // is currently unread (we don't want a "mark N as read" label that
  // includes already-read rows in the count). Read rows hide their
  // checkbox in the row partial, so `selectedIds` from the bulk
  // controller already excludes them — but we filter defensively here.
  _selectedUnreadIds() {
    const boxes = document.querySelectorAll(
      'input[type="checkbox"][data-bulk-select-target="checkbox"]'
    )
    const ids = []
    boxes.forEach(cb => {
      if (!cb.checked) return
      const row = cb.closest(".notification-row")
      if (row && !row.classList.contains("notification-unread")) return
      ids.push(cb.value)
    })
    return ids
  }

  _setLabel(text) {
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent = text
  }

  _setFormAction(url) {
    if (!this.hasFormTarget) return
    this.formTarget.action = url
  }
}
