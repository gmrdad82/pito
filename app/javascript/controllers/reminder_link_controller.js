import { Controller } from "@hotwired/stimulus"

// Phase 7.5 §11h — `[remind me on YYYY-MM-DD]` link.
//
// Wires the 14-day title/handle unlock gate on `/channels/:slug/edit`
// to the Phase 21 JSON endpoint `POST /calendar/entries.json`. On
// click the controller:
//
//   1. Prevents the link's default navigation (the `href` is a `#`
//      sentinel — the form must not lose state).
//   2. Short-circuits to a "Reminder already exists" toast when the
//      same (channel, field, unlock-date) tuple has already been
//      posted from this browser session (localStorage marker).
//   3. POSTs JSON to `/calendar/entries.json` with the milestone_manual
//      payload (the closest user-creatable entry_type — see
//      `CalendarEntry::ENTRY_TYPES` and `Calendar::EntriesController::
//      MANUAL_ENTRY_TYPES`). The endpoint returns the canonical
//      `entry` envelope per `CalendarEntryDecorator#as_detail_json`
//      and may include a top-level `duplicate: "yes"` marker when the
//      server detects the same reminder already exists.
//   4. Renders the outcome as a top-right toast via the shared
//      `.toast-container` (see `shared/_flash_toasts.html.erb` +
//      `toast_controller.js`). The toast auto-dismisses after 4s and
//      can be clicked to dismiss immediately.
//
// Strict no `confirm()` / `alert()` / `prompt()` — the toast is a
// passive flash, not a confirmation prompt (CLAUDE.md hard rule).
//
// External boundary booleans are encoded as `"yes"` / `"no"` strings
// per the yes/no boundary hard rule.
export default class extends Controller {
  static values = {
    unlockDate: String,
    field: String,
    channelId: Number,
    channelName: String,
    timezone: { type: String, default: "UTC" },
    endpoint: { type: String, default: "/calendar/entries.json" }
  }

  create(event) {
    event.preventDefault()

    if (this._alreadyMarked()) {
      this._flashToast(
        `reminder already exists for ${this.unlockDateValue}`,
        "toast-warning"
      )
      return
    }

    const payload = this._buildPayload()
    const headers = this._buildHeaders()

    fetch(this.endpointValue, {
      method: "POST",
      headers,
      credentials: "same-origin",
      body: JSON.stringify(payload)
    })
      .then((response) => this._handleResponse(response))
      .catch(() => {
        this._flashToast(
          "couldn't create reminder; try again.",
          "toast-error"
        )
      })
  }

  _buildPayload() {
    // Channel-id intentionally OMITTED from the payload: the
    // CalendarEntry cross-reference validator forbids `channel_id`
    // on every user-creatable entry_type (milestone_manual, custom,
    // game_release, purchase_planned). The link back to the channel
    // lives in the human-readable title body ("Channel … unlock —
    // <name>"), which the user opens from `/calendar` to navigate
    // back. `milestone_manual` is the loosest user-creatable shape
    // (no required FK, no metadata schema), so it carries the
    // reminder cleanly.
    return {
      calendar_entry: {
        entry_type: "milestone_manual",
        title: this._composeTitle(),
        starts_at: this.unlockDateValue,
        all_day: "yes",
        timezone: this.timezoneValue
      }
    }
  }

  _composeTitle() {
    const name = this.hasChannelNameValue && this.channelNameValue
      ? this.channelNameValue
      : "this channel"
    const gate = this.fieldValue === "handle" ? "handle" : "title"
    return `Channel ${gate} unlock — ${name}`
  }

  _buildHeaders() {
    const headers = {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-Requested-With": "XMLHttpRequest"
    }
    const token = this._csrfToken()
    if (token) headers["X-CSRF-Token"] = token
    return headers
  }

  _csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.getAttribute("content") : null
  }

  _handleResponse(response) {
    if (response.status === 201 || response.status === 200) {
      return response.json().then((data) => this._handleSuccess(response, data))
    }
    return response.json()
      .catch(() => ({}))
      .then(() => {
        this._flashToast(
          "couldn't create reminder; try again.",
          "toast-error"
        )
      })
  }

  _handleSuccess(response, data) {
    const duplicate =
      data && (data.duplicate === "yes" || (data.entry && data.entry.duplicate === "yes"))
    this._mark()
    if (duplicate || response.status === 200) {
      this._flashToast(
        `reminder already exists for ${this.unlockDateValue}`,
        "toast-warning"
      )
    } else {
      this._flashToast(
        `reminder created for ${this.unlockDateValue}.`,
        "toast-success"
      )
    }
  }

  _markerKey() {
    return [
      "pito-reminder",
      this.channelIdValue,
      this.fieldValue,
      this.unlockDateValue
    ].join(":")
  }

  _alreadyMarked() {
    try {
      return window.localStorage.getItem(this._markerKey()) === "1"
    } catch (_e) {
      return false
    }
  }

  _mark() {
    try {
      window.localStorage.setItem(this._markerKey(), "1")
    } catch (_e) {
      // best-effort only
    }
  }

  _flashToast(message, variant = "toast-notice") {
    const container = document.querySelector(".toast-container")
    if (!container) return
    const toast = document.createElement("div")
    toast.className = `toast ${variant}`
    toast.setAttribute("role", "status")
    toast.setAttribute("data-controller", "toast")
    toast.textContent = message
    container.appendChild(toast)
  }
}
