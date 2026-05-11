import { Controller } from "@hotwired/stimulus"

// Phase 27 follow-up (2026-05-11) — Collections modal trigger.
//
// Mounted on each `.collection-tile` anchor in the `/games`
// collections shelf. On click:
//   1. `event.preventDefault()` so the fallback href
//      (`/collections/<slug>`) does NOT navigate when JS is present.
//   2. Set the layout-level Turbo Frame's `src` to the per-collection
//      games-pane URL exposed via the `url` Stimulus value. Turbo
//      fetches that URL and swaps in the games grid.
//   3. Update the modal title text from the `title` Stimulus value.
//   4. Open the dialog via `.showModal()`.
//
// JS-off path: the anchor's plain `href="/collections/<slug>"`
// fallback still works — full-page navigation to the collection show
// page.
//
// NO `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static values = {
    url:      String,
    title:    String,
    dialogId: { type: String, default: "collections-modal" },
    frameId:  { type: String, default: "collections_modal_frame" },
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
    // `data-collections-modal-target="title"`.
    if (this.titleValue) {
      const titleEl = dialog.querySelector('[data-collections-modal-target="title"]')
      if (titleEl) titleEl.textContent = this.titleValue
    }

    if (typeof dialog.showModal === "function" && !dialog.open) {
      dialog.showModal()
    }
  }
}
