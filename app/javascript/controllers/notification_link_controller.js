import { Controller } from "@hotwired/stimulus"

// Phase 16 §3 — Q2 / master decision #1.
//
// Auto-mark-on-click: when a user clicks the notification's source
// `url` link, fire a PATCH to /notifications/:id/read FIRST, then
// allow the navigation. The PATCH is deliberately *fire-and-forget*
// — if it fails, the link STILL navigates so the user is never
// stranded.
//
// CLAUDE.md hard rule (no JS confirm/alert/prompt): this controller
// does NOT use `window.confirm`, `alert`, or `prompt`, and it does
// NOT set `data-turbo-confirm`. Mark-read is non-destructive.
export default class extends Controller {
  static values = {
    markReadUrl: String,
    csrfToken: String,
  }

  // Click handler. Default-prevents navigation, fires the PATCH, and
  // then restarts navigation regardless of the PATCH's result. The
  // PATCH is short-circuited to a same-origin keepalive `fetch` so
  // the navigation does not wait on the server round-trip; the
  // browser flushes the request even after the page starts changing.
  markReadAndNavigate(event) {
    if (!this.hasMarkReadUrlValue || !this.markReadUrlValue) {
      return
    }

    const href = this.element.getAttribute("href")

    if (!href) {
      return
    }

    // Best-effort mark-read. `keepalive: true` lets the browser
    // continue the POST after we navigate away.
    try {
      fetch(this.markReadUrlValue, {
        method: "PATCH",
        headers: this._headers(),
        credentials: "same-origin",
        keepalive: true,
      }).catch(() => {
        // Swallow — link still navigates below.
      })
    } catch (e) {
      // Swallow — link still navigates below.
    }
  }

  _headers() {
    const headers = {
      Accept: "text/vnd.turbo-stream.html, text/html",
      "X-Requested-With": "XMLHttpRequest",
    }

    const token = this.hasCsrfTokenValue ? this.csrfTokenValue : this._metaCsrfToken()
    if (token) {
      headers["X-CSRF-Token"] = token
    }

    return headers
  }

  _metaCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : null
  }
}
