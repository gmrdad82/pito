import { Controller } from "@hotwired/stimulus"

// Phase 27 follow-up (2026-05-17) — Bundles modal inline title edit.
//
// Used by the `/games` bundles modal heading to flip the title text
// between a static display and an inline `<input>` + [update][cancel]
// pair. Submission PATCHes the bundle name as JSON (the controller
// responds 200 with the JSON payload on success); on success the
// display swaps back inline with the new title — no page reload.
//
// The bundles modal is layout-positioned (one `<dialog>` per page)
// and the title swaps per bundle on open via the
// `bundles-modal-trigger` controller. That same trigger writes the
// per-bundle PATCH URL onto this controller's `urlValue` each time a
// bundle opens, so this controller does not need to know which
// bundle it is editing until the user clicks `[change]`.
//
// NO JS `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
// `Escape` triggers `cancel`, never the browser's confirm dialog.
export default class extends Controller {
  static targets = ["display", "editing", "input"]
  static values = { url: String }

  // Inner text node used both for read-back (cancel revert) and
  // write-back (post-save). The bundles-modal-trigger controller
  // sets this element's textContent on every modal open, so the
  // inline-edit display state always reflects the currently-opened
  // bundle.
  titleTextEl() {
    return this.displayTarget.querySelector(".bundle-modal-title-text")
  }

  edit(event) {
    if (event) event.preventDefault()
    this.inputTarget.value = this.titleTextEl().textContent.trim()
    this.displayTarget.hidden = true
    this.editingTarget.hidden = false
    // Defer focus to the next frame so the input is laid out first
    // (it was `hidden` until the line above).
    requestAnimationFrame(() => {
      this.inputTarget.focus()
      this.inputTarget.select()
    })
  }

  cancel(event) {
    if (event) event.preventDefault()
    this.inputTarget.value = this.titleTextEl().textContent.trim()
    this.swapToDisplay()
  }

  save(event) {
    if (event) event.preventDefault()
    const newName = this.inputTarget.value.trim()
    if (newName.length === 0) return // non-blank validation
    if (this.submitting) return      // race guard — ignore double click
    if (!this.urlValue) return       // no bundle bound yet

    this.submitting = true

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf || "",
      },
      body: JSON.stringify({ bundle: { name: newName } }),
    })
      .then(async (r) => {
        // Parse the JSON body either way — the controller returns
        // `{ id, name }` on 200 and `{ errors: [...] }` on 422.
        // Fall back to a generic message if the body isn't JSON
        // (network blip, 500, proxy interception).
        let payload = null
        try { payload = await r.json() } catch (_) { /* swallow */ }
        if (!r.ok) {
          const message =
            (payload && Array.isArray(payload.errors) && payload.errors.length > 0)
              ? payload.errors.join(", ")
              : `could not update bundle (HTTP ${r.status}).`
          this._flashToast(message, "toast-error")
          return
        }
        // Update the modal title text inline.
        this.titleTextEl().textContent = newName
        this.swapToDisplay()
        // 2026-05-18 (Bug 2 fix) — propagate the rename to the bundle
        // tile in the /games shelf so the cover-strip caption updates
        // without a page reload. The PATCH response carries the
        // canonical `{ id, name }` payload; resolve the matching
        // `#bundle-tile-<id>` anchor (rendered by
        // `Game::BundleTileComponent`) and rewrite its
        // `.bundle-tile-name` caption + the anchor's `title` attribute
        // (hover tooltip) + `aria-label` if present. Other surfaces
        // (the bundles modal header, the per-bundle delete-confirm
        // dialog title, /bundles/:id show page) still resolve their
        // labels server-side; those would need a Turbo Stream
        // round-trip to stay in lockstep but are out of scope for
        // this bug.
        if (payload && payload.id != null) {
          const tile = document.getElementById(`bundle-tile-${payload.id}`)
          if (tile) {
            const captionEl = tile.querySelector(".bundle-tile-name")
            if (captionEl) captionEl.textContent = newName
            tile.setAttribute("title", newName)
            tile.setAttribute("data-bundles-modal-trigger-title-value", newName)
          }
        }
        this._flashToast("bundle updated.", "toast-notice")
      })
      .catch((err) => {
        // Network-level failure (fetch rejected, no response). Keep
        // the editing state so the user can retry. No JS
        // alert/confirm per the project's hard rule — surface via
        // the toast region instead.
        console.error("[inline-title-edit] save failed:", err)
        this._flashToast("could not update bundle.", "toast-error")
      })
      .finally(() => {
        this.submitting = false
      })
  }

  // Append a top-right toast into the layout-rendered
  // `.toast-container`. Mirrors `clipboard_copy_controller#_flashToast`
  // so the bundles modal can fire flashes without a full page
  // navigation — the JSON `update` action has no server-rendered
  // flash surface of its own, and Stimulus's MutationObserver picks
  // up the injected `data-controller="toast"` to auto-dismiss.
  _flashToast(message, toastClass = "toast-notice") {
    const container = document.querySelector(".toast-container")
    if (!container) return
    const toast = document.createElement("div")
    toast.className = `toast ${toastClass}`
    toast.textContent = message
    toast.setAttribute("data-controller", "toast")
    toast.setAttribute("role", "status")
    container.appendChild(toast)
  }

  handleKey(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.save(event)
    } else if (event.key === "Escape") {
      event.preventDefault()
      // Stop propagation so the surrounding `<dialog>` does NOT also
      // close on the same Escape press — the user pressed Escape to
      // dismiss the edit, not the modal.
      event.stopPropagation()
      this.cancel(event)
    }
  }

  swapToDisplay() {
    this.displayTarget.hidden = false
    this.editingTarget.hidden = true
  }

  // 2026-05-17 — Reset hook driven by `bundles-modal-reset` on the
  // surrounding <dialog>'s `close` event so the next modal open
  // always starts in the display state, with no stale per-bundle
  // PATCH URL bound and no leftover input value. Without this, an
  // edit-in-progress (display:hidden, editing:visible, input filled,
  // urlValue=bundleA) leaks into the next bundle's modal open.
  reset() {
    if (this.hasInputTarget) this.inputTarget.value = ""
    this.urlValue = ""
    this.submitting = false
    this.swapToDisplay()
  }
}
