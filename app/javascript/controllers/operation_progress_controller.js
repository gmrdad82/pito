import { Controller } from "@hotwired/stimulus"

// Handles the case where a bulk operation finishes before ActionCable connects.
// Once the cable subscription is confirmed, fetches the current operation state
// and patches the DOM if the job has already progressed or completed.
export default class extends Controller {
  static values = { url: String, total: Number }

  connect() {
    this._subscribed = false

    // Listen for Turbo cable subscription confirmation
    document.addEventListener("turbo:cable-stream-source:connected", this._onCableConnected = () => {
      this._subscribed = true
      this._checkStatus()
    })

    // Fallback: if cable doesn't connect within 3s, check anyway
    this._fallbackTimer = setTimeout(() => {
      if (!this._subscribed) this._checkStatus()
    }, 3000)
  }

  disconnect() {
    document.removeEventListener("turbo:cable-stream-source:connected", this._onCableConnected)
    clearTimeout(this._fallbackTimer)
    clearInterval(this._pollTimer)
  }

  async _checkStatus() {
    try {
      const resp = await fetch(this.urlValue, { headers: { "Accept": "application/json" } })
      if (!resp.ok) return

      const data = await resp.json()
      this._applyState(data)

      // If still running/pending, poll every 2s as backup
      if (data.status === "pending" || data.status === "running") {
        this._pollTimer = setInterval(() => this._poll(), 2000)
      }
    } catch (e) {
      // Silently fail — cable broadcasts are the primary mechanism
    }
  }

  async _poll() {
    try {
      const resp = await fetch(this.urlValue, { headers: { "Accept": "application/json" } })
      if (!resp.ok) return

      const data = await resp.json()
      this._applyState(data)

      if (data.status === "completed" || data.status === "failed") {
        clearInterval(this._pollTimer)
      }
    } catch (e) {
      // ignore
    }
  }

  _applyState(data) {
    const { kind, status, current, total, items } = data

    // Update per-item status indicators
    items.forEach(item => {
      const el = document.getElementById(`item_status_${item.id}`)
      if (!el) return

      if (item.status === "succeeded" && !el.querySelector(".status-badge--success")) {
        // 2026-05-11 polish (Fix 1) — render the StatusBadge `done`
        // markup directly so the JS-injected variant matches the
        // ERB-side `StatusBadgeComponent.new(label: "done", kind: :success)`.
        // Literal static markup; no user-supplied data threads through here.
        el.innerHTML = `<span class="status-badge status-badge--success">done</span>`
      } else if (item.status === "failed" && !el.querySelector(".dot-fail")) {
        el.innerHTML = `<span class="dot-fail">fail</span>`
      } else if (item.status === "skipped" && !el.querySelector(".skip-badge")) {
        el.innerHTML = `<span class="bracketed text-danger skip-badge">[ skip ]</span>`
      }
    })

    // Update progress bar
    const progressEl = document.getElementById("operation_progress")
    if (!progressEl) return

    if (status === "completed") {
      const msg = kind === "bulk_sync"
        ? "completed — all items synced successfully."
        : "completed — all items deleted successfully."
      progressEl.innerHTML = `<span class="indicator-up">${msg}</span>`
    } else if (status === "failed") {
      const msg = kind === "bulk_sync"
        ? "failed — one or more items could not be synced."
        : "failed — transaction rolled back, no changes were made."
      progressEl.innerHTML = `<span class="indicator-down">${msg}</span>`
    } else if (current > 0) {
      const barWidth = 30
      const filled = Math.round((current / total) * barWidth)
      const empty = barWidth - filled
      progressEl.innerHTML = `<span class="text-muted">[${"#".repeat(filled)}${".".repeat(empty)}] ${current}/${total}</span>`
    }
  }
}
