import { Controller } from "@hotwired/stimulus"

/**
 * tui-sync-indicator — thin delegator for Tui::SyncIndicatorComponent.
 *
 * Phase 1C (2026-05-24) — checkbox-style, word-only. All visual animation
 * (scramble-settle, color-crossfade, shimmer) is delegated to the
 * colocated tui-transition outlet via setValue / setColor / setShimmer.
 * This controller's only job is event translation: cable lifecycle +
 * activity events on document → setState calls on the outlet.
 *
 * State model:
 *
 *   Three states; "disconnected" is DROPPED — cable drops show as :idle.
 *   The indicator reflects actual ongoing work, not cable connectivity.
 *
 *   Sidekiq stats (kind="sidekiq" or "data" alias):
 *     - busy > 0 OR enqueued > 0 OR retry > 0  →  setActive (sticky)
 *     - all zeros                               →  setIdle (after cool-down)
 *
 *   tui:sync-changed (explicit state from cable):
 *     detail.state ∈ { "idle" | "active" | "paused" }
 *     - paused  → setPaused (future per-panel pause wiring)
 *     - active  → setActive
 *     - idle    → setIdle
 *     (any "disconnected" or legacy state name is treated as idle)
 *
 *   Other cable kinds are ignored here.
 *
 * Canonical display strings (checkbox glyph + word):
 *   idle   → "[ ] sync"  (muted color; no shimmer)
 *   active → "[x] sync"  (accent color; shimmer)
 *   paused → "[-] sync"  (accent-pale color; no shimmer)
 *
 * Full display strings are seeded as data-* attrs by the VC so this JS
 * layer never reconstructs glyphs or inlines English.
 *
 * Sequencing rule (shimmer ↔ scramble, never overlap):
 *
 *   forward (idle → active):
 *     1. _shimmerOnSettle = true    // arm deferred shimmer-on
 *     2. setShimmer(false)          // clear stale shimmer
 *     3. setColor("accent")
 *     4. setValue(word)             // scramble starts
 *     5. on tui-transition:settled  // flag still true → setShimmer(true)
 *
 *   reverse (anything → idle / paused):
 *     1. _shimmerOnSettle = false   // disarm BEFORE scramble starts
 *     2. setShimmer(false)          // shimmer off FIRST
 *     3. setColor("muted" | "accent-pale")
 *     4. setValue(word)             // scramble back; settled fires but flag is off
 *
 * Idempotency: each setter checks the current outlet value. If already
 * in the target state, the methods short-circuit.
 *
 * Debounce-off cool-down: active broadcasts set state immediately.
 * idle broadcasts arm a COOL_DOWN_MS timer; another active broadcast
 * during cool-down cancels it and state stays active.
 */
export default class extends Controller {
  static outlets = ["tui-transition"]
  static values = {
    idle: String,
    active: String,
    paused: String
  }

  static COOL_DOWN_MS = 1000

  connect() {
    this._shimmerOnSettle = false
    this._settledAttachedTo = null
    this._coolDownTimer = null
    this._boundExplicit = this.onExplicitState.bind(this)
    this._boundActivity = this.onActivity.bind(this)
    this._boundSettled = this.onTransitionSettled.bind(this)
    document.addEventListener("tui:sync-changed", this._boundExplicit)
    document.addEventListener("tui:cable-activity", this._boundActivity)
  }

  disconnect() {
    document.removeEventListener("tui:sync-changed", this._boundExplicit)
    document.removeEventListener("tui:cable-activity", this._boundActivity)
    if (this._settledAttachedTo) {
      this._settledAttachedTo.removeEventListener("tui-transition:settled", this._boundSettled)
      this._settledAttachedTo = null
    }
    if (this._coolDownTimer) {
      clearTimeout(this._coolDownTimer)
      this._coolDownTimer = null
    }
  }

  // ─── event handlers ───────────────────────────────────────────────
  onExplicitState(event) {
    const state = event?.detail?.state
    if (!state) return
    if (state === "paused") {
      this.setPaused()
    } else if (state === "active") {
      this.setActive()
    } else {
      // "idle", "synced" (legacy), "syncing" (legacy), "disconnected"
      // (dropped) — all map to idle
      this.setIdle()
    }
  }

  // Sidekiq-aware activity handler. Only Sidekiq stats drive the
  // active/idle state. Other cable kinds are ignored.
  //
  // Debounce-off: active → setActive immediately + cancel any pending
  // cool-down. all-zero → arm a COOL_DOWN_MS timer; only setIdle after
  // the timer expires with no intervening active broadcast.
  onActivity(event) {
    const detail = event?.detail || {}
    const { kind, payload } = detail
    if (kind !== "sidekiq" && kind !== "data") return
    if (this.sidekiqActive(payload)) {
      if (this._coolDownTimer) {
        clearTimeout(this._coolDownTimer)
        this._coolDownTimer = null
      }
      this.setActive()
    } else {
      if (this._coolDownTimer) clearTimeout(this._coolDownTimer)
      this._coolDownTimer = setTimeout(() => {
        this.setIdle()
        this._coolDownTimer = null
      }, this.constructor.COOL_DOWN_MS)
    }
  }

  onTransitionSettled() {
    if (this._shimmerOnSettle && this.hasTuiTransitionOutlet) {
      this.tuiTransitionOutlet.setShimmer(true)
    }
  }

  // ─── delegation to tui-transition outlet ──────────────────────────
  setActive() {
    const c = this.transitionController()
    if (!c) return
    this.ensureSettledListenerAttached()
    this._shimmerOnSettle = true
    if (this.currentValue() === this.wordFor("active")) return
    c.setShimmer(false)
    c.setColor("accent")
    c.setValue(this.wordFor("active"))
  }

  setIdle() {
    const c = this.transitionController()
    if (!c) return
    this._shimmerOnSettle = false
    if (this.currentValue() === this.wordFor("idle")) {
      c.setShimmer(false)
      return
    }
    c.setShimmer(false)
    c.setColor("muted")
    c.setValue(this.wordFor("idle"))
  }

  setPaused() {
    const c = this.transitionController()
    if (!c) return
    this._shimmerOnSettle = false
    if (this.currentValue() === this.wordFor("paused")) {
      c.setShimmer(false)
      return
    }
    c.setShimmer(false)
    c.setColor("accent-pale")
    c.setValue(this.wordFor("paused"))
  }

  // ─── helpers ──────────────────────────────────────────────────────
  // `dead` is intentionally NOT included. Jobs in Sidekiq's dead set
  // are terminal failures, not active work. The sync indicator reflects
  // ongoing work (busy / enqueued / retry); dead-set count is surfaced
  // separately by the `d<N>` segment on tui-sidekiq-stats.
  sidekiqActive(payload) {
    if (!payload || typeof payload !== "object") return false
    const b = parseInt(payload.busy || 0, 10) || 0
    const e = parseInt(payload.enqueued || 0, 10) || 0
    const r = parseInt(payload.retry || 0, 10) || 0
    return b > 0 || e > 0 || r > 0
  }

  transitionController() {
    if (this.hasTuiTransitionOutlet) return this.tuiTransitionOutlet
    return null
  }

  ensureSettledListenerAttached() {
    if (!this.hasTuiTransitionOutlet) return
    const target = this.tuiTransitionOutlet.element
    if (this._settledAttachedTo === target) return
    if (this._settledAttachedTo) {
      this._settledAttachedTo.removeEventListener("tui-transition:settled", this._boundSettled)
    }
    target.addEventListener("tui-transition:settled", this._boundSettled)
    this._settledAttachedTo = target
  }

  currentValue() {
    if (!this.hasTuiTransitionOutlet) return null
    return this.tuiTransitionOutlet.valueValue
  }

  wordFor(stateName) {
    if (stateName === "idle")   return this.idleValue
    if (stateName === "active") return this.activeValue
    if (stateName === "paused") return this.pausedValue
    return stateName
  }
}
