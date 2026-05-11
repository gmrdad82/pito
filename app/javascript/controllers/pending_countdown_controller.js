// Phase 25 — 01b (Q-J). Client-side countdown timer on
// `/login/pending`.
//
// Reads `data-pending-countdown-deadline-value` (ISO 8601) and ticks
// down once per second, rendering `MM:SS` into the `display` target.
// When the deadline elapses, the controller reloads the page so the
// server-side `Login::PendingsController#show` action surfaces the
// terminal copy (the sweeper has flipped the row to `:expired`, or
// will within the minute).
//
// The deadline is server-time-authoritative. The countdown is just a
// UX hint; the actual expiry decision lives in
// `Auth::PendingSessionExpirer` + the controller's
// state-pending-approval? check.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display"]
  static values = { deadline: String }

  connect() {
    this.deadlineTime = this.parseDeadline()
    if (this.deadlineTime === null) {
      // No deadline; nothing to count down.
      return
    }
    this.tick()
    this.intervalId = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.intervalId) {
      clearInterval(this.intervalId)
      this.intervalId = null
    }
  }

  parseDeadline() {
    const raw = this.deadlineValue
    if (!raw) return null
    const parsed = Date.parse(raw)
    if (Number.isNaN(parsed)) return null
    return parsed
  }

  tick() {
    if (!this.hasDisplayTarget) return
    const now = Date.now()
    const remainingMs = Math.max(0, this.deadlineTime - now)
    this.displayTarget.textContent = this.formatRemaining(remainingMs)

    if (remainingMs <= 0) {
      // Stop the timer and reload so the server renders the expired
      // copy. The reload reaches `show` which redirects on expiry.
      if (this.intervalId) {
        clearInterval(this.intervalId)
        this.intervalId = null
      }
      window.location.reload()
    }
  }

  formatRemaining(ms) {
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    const mm = String(minutes).padStart(2, "0")
    const ss = String(seconds).padStart(2, "0")
    return `${mm}:${ss}`
  }
}
