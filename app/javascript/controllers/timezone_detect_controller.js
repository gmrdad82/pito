import { Controller } from "@hotwired/stimulus"

// Phase 26 — 01a. Timezone foundation.
//
// Mounted on the layout `<body>`. On connect, the controller checks
// the data-attribute it was given (`data-timezone-detect-stored-value`,
// rendered server-side from `Current.user&.time_zone`). If the stored
// zone is the sentinel "Etc/UTC" (meaning the user has never picked a
// zone), the controller reads the browser-detected zone via
//
//   Intl.DateTimeFormat().resolvedOptions().timeZone
//
// and silently PATCHes `/settings/time_zone`. No JS confirm / alert /
// prompt — the detect is invisible. The server responds with 204 on
// success or 422 on a validation failure (e.g. a browser that returns
// a zone name Rails doesn't recognize). Either way the controller does
// nothing more — subsequent loads see the new stored value and skip
// the detect.
//
// The server's `Sessions::AuthConcern` guards the PATCH endpoint with
// cookie-session auth; the unauthenticated layout (login form, OAuth
// consent screen) does NOT mount this controller because
// `Current.user` is nil and the body attribute is omitted in those
// layouts. Defensive: the controller bails if the stored value is
// missing or empty.
export default class extends Controller {
  static values = {
    stored: String,
    url: String,
    csrf: String
  }

  connect() {
    // Bail when the layout didn't render the data — the controller is
    // mounted globally on `<body>` but only carries the data on
    // authenticated pages.
    if (!this.hasStoredValue || !this.storedValue) return

    // Only detect on the "never set" sentinel — every subsequent load
    // sees a real zone and skips silently.
    if (this.storedValue !== "Etc/UTC") return

    let detected = null
    try {
      detected = Intl.DateTimeFormat().resolvedOptions().timeZone
    } catch (_e) {
      // Older browsers / locked-down WebViews may throw. Silent
      // fallback — the user stays on Etc/UTC and can pick a zone via
      // the Settings dropdown.
      return
    }

    if (!detected || detected === "Etc/UTC" || detected === "UTC") return

    const url = this.hasUrlValue ? this.urlValue : "/settings/time_zone"

    const body = new FormData()
    body.append("time_zone", detected)

    const headers = { "Accept": "application/json" }
    if (this.hasCsrfValue && this.csrfValue) {
      headers["X-CSRF-Token"] = this.csrfValue
    } else {
      const meta = document.querySelector('meta[name="csrf-token"]')
      if (meta && meta.content) headers["X-CSRF-Token"] = meta.content
    }

    fetch(url, {
      method: "PATCH",
      headers: headers,
      credentials: "same-origin",
      body: body
    }).catch(() => {
      // Silent failure. The user can still pick a zone manually
      // from /settings.
    })
  }
}
