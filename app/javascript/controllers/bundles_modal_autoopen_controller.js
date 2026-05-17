import { Controller } from "@hotwired/stimulus"

// 2026-05-18 — Bundles modal auto-open.
//
// Mounted on the `<dialog id="bundles-modal">` shell ONLY when the
// modal partial is rendered with a `bundle:` local (i.e. from the
// `BundlesController#create` Turbo Stream response). The steady-state
// render in `_bundles_for_shelf` omits this controller; the dialog
// stays closed until a tile click fires `bundles-modal-trigger#open`.
//
// On `connect()` the controller calls `showModal()` so the user lands
// directly inside the freshly-created bundle without an extra click.
// `bundles-modal-reset` (sibling controller on the same element) is
// also mounted, so when the user closes this auto-opened dialog the
// transient state (title text, inline-edit URL, Turbo Frame contents)
// gets torn down — the next pre-existing-bundle open via
// `bundles-modal-trigger` starts from a clean slate.
//
// NO JS `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  connect() {
    if (typeof this.element.showModal !== "function") return
    if (this.element.open) return
    // The Turbo Stream's `replace` swaps the dialog node in atomically.
    // Stimulus' `connect()` fires synchronously inside the
    // morph/replace pass; `showModal()` is safe to call at that point
    // because the new node is already in the DOM tree.
    this.element.showModal()
  }
}
