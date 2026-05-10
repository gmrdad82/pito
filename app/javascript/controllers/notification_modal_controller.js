import { Controller } from "@hotwired/stimulus"

// Phase 16 §3 UX restructure 2026-05-10 — open notification detail in a
// modal instead of a full-page navigation.
//
// The controller is mounted on a single `<dialog>` element rendered once
// by the index page. Row links carry
// `data-action="click->notification-modal#open"` and
// `data-notification-modal-url-value="/notifications/:id"`. The click
// handler:
//
//   1. Prevents the default navigation.
//   2. Sets the `notification_detail_frame` Turbo Frame's `src` to the
//      target URL — Turbo fetches and swaps the frame content, which is
//      the show.html.erb template wrapped in a matching frame tag.
//   3. Calls `dialog.showModal()` so the dialog renders on top.
//
// The auto-mark-read behaviour is preserved: the show page renders the
// `notification-link` Stimulus controller on the `[ open ]` link, AND
// the modal's mark-read button posts via the existing PATCH endpoint.
//
// Closing semantics:
//
//   - Escape key — handled by the native <dialog> (no custom code).
//   - Click outside — `clickOutside` action, mirrors the confirm-modal
//     and saved-views patterns.
//   - `[ back ]` / `[ close ]` — bracketed link with
//     `data-action="click->notification-modal#close"`.
export default class extends Controller {
  static targets = ["dialog", "frame"]
  static values  = { url: String }

  // Open the modal. Invoked from a row link. The clicking element
  // carries the target URL on `data-notification-modal-url-value`,
  // which Stimulus surfaces via `event.params.url` on the click target
  // when the controller is mounted on the dialog (different element).
  // To keep the API uniform we read the URL from the clicked anchor's
  // `href` attribute as the source of truth — that gracefully degrades
  // if JS is disabled (link still navigates to the show page).
  open(event) {
    if (event) event.preventDefault()
    const anchor = event && event.currentTarget
    const url = (anchor && anchor.getAttribute("href")) || this.urlValue
    if (!url) return

    if (this.hasFrameTarget) {
      // Setting `src` triggers Turbo to fetch and swap the frame.
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
    // Clear the frame's src so the next open re-fetches fresh content
    // (read state may have changed between opens).
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
