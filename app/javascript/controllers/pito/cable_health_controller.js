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
import { showRefreshNudge } from "controllers/pito/refresh_nudge_controller"

const HIDDEN_RELOAD_MS = 30000 // reload if tab was hidden longer than this

export default class extends Controller {
  connect() {
    this.hiddenAt = null
    this.#bindVisibility()
    this.#watchCableReconnect()
    this.#watchConnectionDot()
  }

  disconnect() {
    this.visibilityAbort?.abort()
    this.reconnectObserver?.disconnect()
    this.dotObserver?.disconnect()
    document.removeEventListener("turbo:before-stream-render", this.onCableActivity)
  }

  // ── The connection dot (owner state machine, 2026-07-12) ────────────────────
  //
  // #pito-conn-dot renders the plug-zap icon (orange, connecting) for an
  // authenticated user; this flips data-state to "connected" (the green cable
  // icon) while any cable stream reports `connected`, back on a drop, and
  // fires the one-shot SPARK (a dash racing the cable's stroke) per cable
  // activity. Idle = static. Unauthenticated dots are the red lock and never
  // wired here (data-authenticated=false).

  #watchConnectionDot() {
    const dot = document.getElementById("pito-conn-dot")
    if (!dot || dot.dataset.authenticated !== "true") return

    const paint = () => {
      const connected = [...document.querySelectorAll("turbo-cable-stream-source")]
        .some((s) => s.hasAttribute("connected"))
      // The icons swap via CSS on this attribute: cable/green when connected,
      // plug-zap/orange while connecting or dropped.
      dot.dataset.state = connected ? "connected" : "connecting"
    }
    paint()

    this.dotObserver = new MutationObserver(paint)
    document.querySelectorAll("turbo-cable-stream-source").forEach((s) =>
      this.dotObserver.observe(s, { attributes: true, attributeFilter: ["connected"] }),
    )

    this.onCableActivity = () => {
      dot.classList.remove("pito-cable-active")
      void dot.offsetWidth // restart the spark for back-to-back activity
      dot.classList.add("pito-cable-active")
    }
    document.addEventListener("turbo:before-stream-render", this.onCableActivity)
    dot.addEventListener("animationend", () => dot.classList.remove("pito-cable-active"))
  }

  // ── The refresh nudge ──────────────────────────────────────────────────────
  //
  // When the server is updated (pito update / autoupdate), the old container
  // dies with every WebSocket in it; ActionCable silently reconnects this tab
  // to the NEW server — but the DOM keeps the old build's CSS/JS until a real
  // reload. Detection is CLIENT-side on reconnect (a server broadcast on boot
  // would race the reconnections; ActionCable has no replay): Turbo toggles a
  // `connected` attribute on its <turbo-cable-stream-source>, so a
  // MutationObserver sees drop → return; on return we compare GET /version
  // with the page's `pito-version` meta and clone the layout's nudge template
  // into the scrollback on mismatch. Once per page life — the nudge asks for
  // the reload that replaces this DOM anyway.

  #watchCableReconnect() {
    this.pageVersion = document.querySelector('meta[name="pito-version"]')?.content || null
    this.sawDisconnect = false
    this.nudged = false

    const sources = document.querySelectorAll("turbo-cable-stream-source")
    if (!this.pageVersion || sources.length === 0) return

    this.reconnectObserver = new MutationObserver(() => {
      const connected = [...document.querySelectorAll("turbo-cable-stream-source")]
        .some((s) => s.hasAttribute("connected"))
      if (!connected) {
        this.sawDisconnect = true
        return
      }
      if (this.sawDisconnect && !this.nudged) {
        this.sawDisconnect = false
        this.#checkVersion()
      }
    })
    sources.forEach((s) =>
      this.reconnectObserver.observe(s, { attributes: true, attributeFilter: ["connected"] }),
    )
  }

  async #checkVersion() {
    try {
      const resp = await fetch("/version", { headers: { "Accept": "application/json" } })
      if (!resp.ok) return // 401 (session died with the update) or blip — next reconnect retries
      const { version } = await resp.json()
      if (version && version !== this.pageVersion) this.#showNudge()
    } catch {
      // Offline blip mid-reconnect — the next reconnect runs the check again.
    }
  }

  #showNudge() {
    if (this.nudged) return
    // Shared with pito--version-watch (the version heartbeat) — consuming the
    // template doubles as the cross-controller once-per-page guard.
    this.nudged = showRefreshNudge()
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
