// Pito::CableHealthController
//
// Monitors connection health to prevent the "stuck after inactivity" bug
// where the ActionCable WebSocket drops and Turbo Stream broadcasts never
// reach the client.
//
// Strategy:
//   1. Ping /up every 30s via fetch — cheap HEAD request.
//   2. On 2 consecutive failures → mark offline (data-pito-cable-offline on body).
//   3. On visibilitychange → visible after tab was hidden > 30s → reload page.
//   4. ChatFormController checks the offline flag before submit; if offline,
//      it reloads instead of submitting.
//
// Usage:
//   <div data-controller="pito--cable-health">

import { Controller } from "@hotwired/stimulus"

const PING_INTERVAL_MS = 30000      // 30s
const OFFLINE_THRESHOLD = 2          // consecutive failures before offline
const HIDDEN_RELOAD_MS   = 30000     // reload if tab hidden longer than this

export default class extends Controller {
  connect() {
    this.failures    = 0
    this.online      = true
    this.hiddenAt    = null
    this.pingTimer   = null

    this.#bindVisibility()
    this.#startPing()
  }

  disconnect() {
    this.#stopPing()
    this.visibilityAbort?.abort()
  }

  // ── visibility ─────────────────────────────────────────────────────────────

  #bindVisibility() {
    this.visibilityAbort = new AbortController()
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") {
        this.hiddenAt = Date.now()
      } else {
        const wasHidden = this.hiddenAt && (Date.now() - this.hiddenAt) > HIDDEN_RELOAD_MS
        if (wasHidden || !this.online) {
          window.location.reload()
        }
        this.hiddenAt = null
      }
    }, { signal: this.visibilityAbort.signal })
  }

  // ── ping loop ────────────────────────────────────────────────────────────

  #startPing() {
    this.#ping() // immediate first check
    this.pingTimer = setInterval(() => this.#ping(), PING_INTERVAL_MS)
  }

  #stopPing() {
    clearInterval(this.pingTimer)
  }

  #ping() {
    fetch("/up", { method: "HEAD", cache: "no-store" })
      .then((res) => {
        if (res.ok) {
          this.#markOnline()
        } else {
          this.#markFailure()
        }
      })
      .catch(() => this.#markFailure())
  }

  #markOnline() {
    this.failures = 0
    if (!this.online) {
      this.online = true
      document.body.removeAttribute("data-pito-cable-offline")
    }
  }

  #markFailure() {
    this.failures += 1
    if (this.failures >= OFFLINE_THRESHOLD && this.online) {
      this.online = false
      document.body.setAttribute("data-pito-cable-offline", "true")
    }
  }
}
