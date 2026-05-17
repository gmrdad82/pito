import { Controller } from "@hotwired/stimulus"

// Phase 27 follow-up (2026-05-17) — Bundles modal trigger (formerly
// `collections_modal_trigger_controller.js`).
//
// Mounted on each `.bundle-tile` anchor in the `/games` bundles shelf.
// On click:
//   1. `event.preventDefault()` so the fallback href
//      (`/bundles/<slug>`) does NOT navigate when JS is present.
//   2. Set the layout-level Turbo Frame's `src` to the per-bundle
//      games-pane URL exposed via the `url` Stimulus value. Turbo
//      fetches that URL and swaps in the games grid.
//   3. Update the modal title text from the `title` Stimulus value.
//   4. Open the dialog via `.showModal()`.
//
// JS-off path: the anchor's plain `href="/bundles/<slug>"` fallback
// still works — full-page navigation to the bundle show page.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static values = {
    url:             String,
    title:           String,
    updateUrl:       String,  // PATCH /bundles/:id — feeds the inline-title-edit controller
    deleteConfirmId: String,  // DOM id of the per-bundle confirm-delete dialog
    dialogId:        { type: String, default: "bundles-modal" },
    frameId:         { type: String, default: "bundles_modal_frame" },
    titleId:         { type: String, default: "" },  // optional override
  }

  open(event) {
    if (event) event.preventDefault()

    const dialog = document.getElementById(this.dialogIdValue)
    const frame  = document.getElementById(this.frameIdValue)
    if (!dialog || !frame) return

    if (this.urlValue) {
      frame.setAttribute("src", this.urlValue)
    }

    // Title swap — the modal partial marks the heading with
    // `data-bundles-modal-target="title"`.
    if (this.titleValue) {
      const titleEl = dialog.querySelector('[data-bundles-modal-target="title"]')
      if (titleEl) titleEl.textContent = this.titleValue
    }

    // 2026-05-17 — Write the per-bundle PATCH URL onto the
    // inline-title-edit controller's `urlValue` (via the
    // `urlHolder` target on the modal). The inline-edit controller
    // re-reads `urlValue` on each save so this assignment is enough
    // to bind the next save to the currently-opened bundle.
    if (this.updateUrlValue) {
      const holder = dialog.querySelector('[data-bundles-modal-target="urlHolder"]')
      if (holder) holder.setAttribute("data-inline-title-edit-url-value", this.updateUrlValue)
    }

    // 2026-05-18 — Write the per-bundle delete-confirm dialog id onto
    // the modal's `[-]` button so `click->modal-trigger#open` opens
    // the matching `<dialog id="confirm_delete_bundle_<id>">`. The
    // `modal-trigger` controller re-reads `targetIdValue` from the
    // attribute on each click, so this assignment binds the next
    // delete attempt to the currently-opened bundle.
    if (this.deleteConfirmIdValue) {
      const deleteBtn = dialog.querySelector('[data-bundles-modal-target="deleteButton"]')
      if (deleteBtn) deleteBtn.setAttribute("data-modal-trigger-target-id-value", this.deleteConfirmIdValue)
    }

    if (typeof dialog.showModal === "function" && !dialog.open) {
      dialog.showModal()
    }
  }
}
