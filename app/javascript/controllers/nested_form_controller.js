import { Controller } from "@hotwired/stimulus"

// Phase 11 §01a — Generic nested-attributes editor for forms that
// stack chapter / end-screen / link rows under a single parent
// resource. Mirrors the cocoon / stimulus-rails-nested-form
// pattern but stays in-tree with zero gem dependency.
//
// Markup contract:
//   <fieldset data-controller="nested-form">
//     <div data-nested-form-target="rows">
//       <!-- persisted rows here -->
//     </div>
//     <template data-nested-form-target="template">
//       <!-- one row partial with `__INDEX__` placeholder -->
//     </template>
//     <button type="button" data-action="nested-form#add">[ add ]</button>
//   </fieldset>
//
// Each row partial includes:
//   - data-nested-form-target="row" on the row container
//   - <input type="hidden" name="..._destroy"
//          data-nested-form-target="destroyFlag">
//   - <button type="button" data-action="nested-form#remove">
//
// Hard rule (CLAUDE.md): NO window.confirm / alert / prompt. The
// `[remove]` button hides the row inline; the server destroys on
// submit. There is no "are you sure" gate at this layer — removal
// of a not-yet-submitted change is non-destructive.
export default class extends Controller {
  static targets = ["rows", "template", "row", "destroyFlag"]

  add(event) {
    event?.preventDefault?.()
    if (!this.hasTemplateTarget || !this.hasRowsTarget) return

    const html = this.templateTarget.innerHTML.replace(
      /__INDEX__/g,
      this.uniqueIndex()
    )
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event?.preventDefault?.()
    const row = event.currentTarget.closest('[data-nested-form-target="row"]')
    if (!row) return

    const flag = row.querySelector('[data-nested-form-target="destroyFlag"]')
    if (flag) {
      // Persisted row — flip `_destroy` to 1 and hide. Server
      // destroys on submit.
      flag.value = "1"
      row.style.display = "none"
    } else {
      // Unsaved row — drop from the DOM. Nothing to persist.
      row.remove()
    }
  }

  uniqueIndex() {
    // `Date.now()` is enough for human-paced [add] clicks; collisions
    // would need two clicks in the same millisecond, which Rails'
    // nested-attributes parser would silently merge anyway (worst
    // case: the second row overwrites the first — caller can re-add).
    return Date.now().toString() + Math.floor(Math.random() * 1000).toString()
  }
}
