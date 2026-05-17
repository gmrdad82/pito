import { Controller } from "@hotwired/stimulus"

// Phase 27 follow-up (2026-05-17) — Bundles modal teardown.
//
// Mounted on the persistent `<dialog id="bundles-modal">` shell. The
// modal is layout-positioned (one dialog per page) and content swaps
// in per-bundle via the `bundles-modal-trigger` controller writing
// the Turbo Frame `src`, title text, and inline-edit PATCH URL on
// every open. Because the dialog stays in the DOM across open/close
// cycles, any transient state inside it (inline-title-edit `editing`
// mode, the previous bundle's Turbo Frame contents, the previous
// bundle's PATCH URL) persists across closes and leaks into the
// next open — see the 2026-05-17 bug report.
//
// This controller hooks the `<dialog>`'s native `close` event (which
// fires for every dismissal path — `[close]` button via
// `confirm-modal#close`, ESC native handler, `clickOutside`,
// programmatic `dialog.close()`) and tears down the per-bundle
// state so the next open starts clean:
//
//   1. Reset the inline-title-edit controller back to display mode,
//      clear its `urlValue`, clear the input.
//   2. Clear the title text element (the next open's
//      `bundles-modal-trigger#open` writes the new title before
//      `showModal()` so there is no visible flash).
//   3. Clear the Turbo Frame's `src` AND inner content so the next
//      open re-fetches fresh — Turbo would otherwise keep the
//      previous frame content visible until the new fetch resolves,
//      which is the most visible part of the "old modal still here"
//      symptom.
//
// NO JS `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  connect() {
    this.onClose = this.handleClose.bind(this)
    this.element.addEventListener("close", this.onClose)
  }

  disconnect() {
    if (this.onClose) {
      this.element.removeEventListener("close", this.onClose)
    }
  }

  handleClose() {
    // 1. Inline-title-edit reset (look up the controller instance
    //    via the Stimulus application registry — same pattern the
    //    rest of the codebase uses for cross-controller calls).
    const editRow = this.element.querySelector(
      '[data-controller~="inline-title-edit"]',
    )
    if (editRow) {
      const app = this.application
      if (app && typeof app.getControllerForElementAndIdentifier === "function") {
        const editCtrl = app.getControllerForElementAndIdentifier(
          editRow,
          "inline-title-edit",
        )
        if (editCtrl && typeof editCtrl.reset === "function") {
          editCtrl.reset()
        }
      }
      // Belt-and-braces: also strip the PATCH URL attribute so the
      // next open's `bundles-modal-trigger#open` write is the only
      // source of truth, even if the controller lookup failed for
      // any reason (Stimulus boot ordering, registry edge case).
      editRow.setAttribute("data-inline-title-edit-url-value", "")
    }

    // 2. Title text reset.
    const titleEl = this.element.querySelector(
      '[data-bundles-modal-target="title"]',
    )
    if (titleEl) titleEl.textContent = ""

    // 3. Turbo Frame reset — clear `src` so a future identical
    //    `src` assignment still triggers a fresh fetch, and remove
    //    children so the previous bundle's games composite is not
    //    visible during the next open's lazy fetch.
    //    `replaceChildren()` is the safe DOM-native equivalent of
    //    `innerHTML = ""` — no string parsing, no XSS surface.
    const frame = this.element.querySelector(
      '[data-bundles-modal-target="frame"]',
    )
    if (frame) {
      frame.removeAttribute("src")
      frame.replaceChildren()
    }
  }
}
