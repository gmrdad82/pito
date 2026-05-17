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
    url:      String,
    title:    String,
    dialogId: { type: String, default: "bundles-modal" },
    frameId:  { type: String, default: "bundles_modal_frame" },
    titleId:  { type: String, default: "" },  // optional override
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

    if (typeof dialog.showModal === "function" && !dialog.open) {
      dialog.showModal()
    }
  }
}
