import { Controller } from "@hotwired/stimulus"

// Calendar refactor 2026-05-11 — calendar entry details modal.
//
// Mirrors the notification-modal pattern. Mounted once at the layout
// level wrapping a <dialog>. Each chip (month grid) and row title
// (schedule list) carries:
//
//   data-action="click->calendar-entry-modal#open"
//   data-calendar-entry-modal-url-param="/calendar/entries/:id/details_pane"
//
// The click handler:
//   1. Prevents the default navigation (chips fall back to the entry
//      show page when JS is off).
//   2. Reads the target URL from the Stimulus action param.
//   3. Sets the inner Turbo Frame's `src` so Turbo fetches the details
//      pane and swaps it in.
//   4. Opens the <dialog> via `.showModal()`.
//
// Closing semantics mirror the project's other layout-level modals
// (notification, collections):
//   - Escape         — native <dialog>.
//   - Click outside  — `clickOutside` action.
//   - `[close]` link — `close` action.
//
// NO JS `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  static targets = ["dialog", "frame"]

  open(event) {
    if (event) event.preventDefault()

    // Stimulus surfaces `data-calendar-entry-modal-url-param` on the
    // clicked element as `event.params.url`. Fall back to the
    // element's `href` (chips carry the entry show page URL) so a
    // misconfigured trigger still opens *something* sensible.
    const url =
      (event && event.params && event.params.url) ||
      (event && event.currentTarget && event.currentTarget.getAttribute("href"))
    if (!url || url === "#") return

    if (this.hasFrameTarget) {
      this.frameTarget.setAttribute("src", url)
    }
    if (this.hasDialogTarget && typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget && typeof this.dialogTarget.close === "function") {
      this.dialogTarget.close()
    }
    // Clear the frame src so the next open re-fetches fresh content
    // (e.g. a derived entry's metadata.user_overrides may have
    // changed elsewhere).
    if (this.hasFrameTarget) {
      this.frameTarget.removeAttribute("src")
      this.frameTarget.replaceChildren()
    }
  }

  clickOutside(event) {
    if (event.target === this.dialogTarget) {
      this.close(event)
    }
  }
}
