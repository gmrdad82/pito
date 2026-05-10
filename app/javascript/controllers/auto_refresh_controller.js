import { Controller } from "@hotwired/stimulus"

// Phase 14 §1 polish (2026-05-10) — page-level polling fallback for
// the game show page. While `games.resyncing` is true the page
// stamps this controller and reloads itself every `interval-value`
// ms via Turbo's replace-visit. Once the Sidekiq job clears the
// resyncing flag the next reload re-renders without the controller,
// stopping the polling loop.
//
// Mirrors the smaller `analytics_refresh_polling_controller.js`
// pattern so the polling story stays consistent across the app.
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.timer = setTimeout(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  refresh() {
    if (typeof window.Turbo !== "undefined" && window.Turbo.visit) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }
}
