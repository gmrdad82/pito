// Pito::CableHealthController
//
// Recovers from the "stuck after inactivity" bug: when a tab is hidden long
// enough, the browser throttles timers and the ActionCable WebSocket can drop
// without its monitor noticing — so Turbo Stream broadcasts pile up unseen.
// When the tab becomes visible again after being hidden past the threshold,
// reload to re-establish the cable and backfill anything missed from the DB.
//
// Deliberately NO HTTP health poll. The old version pinged `/up` every 30s and
// flagged the body offline on failure — but `/up` was removed in 0.7.0, so the
// ping 404'd forever and falsely marked the cable dead ~60s into every session,
// which made the chatbox reload-and-discard the next message. An HTTP ping never
// actually proved the WebSocket was alive anyway. ActionCable's own
// ConnectionMonitor handles reconnection while the tab is active, and a new
// message always POSTs over HTTP regardless of cable state — so submitting is
// never gated on connection health.
//
// Usage:
//   <div data-controller="pito--cable-health">

import { Controller } from "@hotwired/stimulus"

const HIDDEN_RELOAD_MS = 30000 // reload if tab was hidden longer than this

export default class extends Controller {
  connect() {
    this.hiddenAt = null
    this.#bindVisibility()
  }

  disconnect() {
    this.visibilityAbort?.abort()
  }

  #bindVisibility() {
    this.visibilityAbort = new AbortController()
    document.addEventListener(
      "visibilitychange",
      () => {
        if (document.visibilityState === "hidden") {
          this.hiddenAt = Date.now()
        } else {
          const wasHidden =
            this.hiddenAt && Date.now() - this.hiddenAt > HIDDEN_RELOAD_MS
          if (wasHidden) window.location.reload()
          this.hiddenAt = null
        }
      },
      { signal: this.visibilityAbort.signal },
    )
  }
}
