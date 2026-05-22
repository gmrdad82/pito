import { Controller } from "@hotwired/stimulus"

/**
 * tui-sync-indicator — thin delegator for Tui::SyncIndicatorComponent.
 *
 * Phase 2A (2026-05-22) — glyph-free, word-only. All visual animation
 * (scramble-settle, color-crossfade, shimmer) is delegated to the
 * colocated tui-transition outlet via setValue / setColor / setShimmer.
 * This controller's only job is event translation: cable lifecycle +
 * activity events on document → setState calls on the outlet.
 *
 * Event contracts:
 *
 *   tui:cable-activity (every cable message)
 *     → flip to "syncing" for PULSE_MS, then back to "synced".
 *       Re-arms the timer on every subsequent activity event so a
 *       burst of traffic keeps the cell purple until the burst quiets.
 *
 *   tui:sync-changed
 *     detail: { state: "synced" | "syncing" | "disconnected" }
 *     → explicit state override. `disconnected` cancels any in-flight
 *       activity pulse; `synced` / `syncing` also pass through but are
 *       normally owned by the activity-pulse path.
 *
 * Canonical color lock (matches Tui::SyncIndicatorComponent#color_for):
 *   synced       → "muted"   // idle / calm
 *   syncing      → "accent"  // active, paired with shimmer
 *   disconnected → "danger"  // cable lifecycle error
 *
 * Sequencing rule (shimmer ↔ scramble, never overlap):
 *
 *   forward (synced → syncing):
 *     1. setShimmer(false)          // clear stale shimmer
 *     2. setColor("accent")
 *     3. setValue(word)             // scramble starts
 *     4. on tui-transition:settled → setShimmer(true)  // via _shimmerOnSettle flag
 *
 *   reverse (anything → synced / disconnected):
 *     1. _shimmerOnSettle = false   // disarm the deferred shimmer-on
 *     2. setShimmer(false)          // shimmer off FIRST
 *     3. setColor("muted" | "danger")
 *     4. setValue(word)             // scramble back
 *
 * Idempotency: setSyncing / setSynced / setDisconnected check the current
 * outlet value first. If already in the target state, they only re-arm the
 * flag (no setShimmer(false) → no flicker, no re-scramble of an
 * already-correct value). This prevents constant churn during continuous
 * cable activity bursts (e.g. a long-running Sidekiq job firing middleware
 * broadcasts on every lifecycle tick).
 *
 * Settled listener strategy: ONE permanent listener (`_boundSettled`)
 * attached to the outlet element on first attach. Gated by the
 * `_shimmerOnSettle` boolean so setSynced/setDisconnected can disarm the
 * deferred shimmer-on between scramble passes. Avoids stale
 * `{ once: true }` arrow listeners firing during the LATER reverse-scramble.
 *
 * Word labels come from data-* values seeded by the VC (sourced from
 * `config/locales/tui/en.yml` `tui.tst.sync.*`) so this JS layer never
 * inlines English strings.
 */
export default class extends Controller {
  static outlets = ["tui-transition"]
  static values = {
    synced: String,
    syncing: String,
    disconnected: String
  }

  // Activity pulse duration in milliseconds. Every `tui:cable-activity`
  // event re-arms this timer; the indicator returns to "synced" only
  // after PULSE_MS of quiet.
  static PULSE_MS = 400

  connect() {
    this._pulseTimer = null
    this._shimmerOnSettle = false
    this._settledAttachedTo = null
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
    if (this._pulseTimer) {
      clearTimeout(this._pulseTimer)
      this._pulseTimer = null
    }
  }

  // ─── event handlers ───────────────────────────────────────────────
  onExplicitState(event) {
    const state = event?.detail?.state
    if (!state) return
    if (state === "disconnected") {
      if (this._pulseTimer) {
        clearTimeout(this._pulseTimer)
        this._pulseTimer = null
      }
      this.setDisconnected()
    } else if (state === "syncing") {
      this.setSyncing()
    } else if (state === "synced") {
      if (this._pulseTimer) {
        clearTimeout(this._pulseTimer)
        this._pulseTimer = null
      }
      this.setSynced()
    }
  }

  onActivity() {
    this.setSyncing()
    if (this._pulseTimer) clearTimeout(this._pulseTimer)
    this._pulseTimer = setTimeout(() => {
      this.setSynced()
      this._pulseTimer = null
    }, this.constructor.PULSE_MS)
  }

  onTransitionSettled() {
    if (this._shimmerOnSettle && this.hasTuiTransitionOutlet) {
      this.tuiTransitionOutlet.setShimmer(true)
    }
  }

  // ─── delegation to tui-transition outlet ──────────────────────────
  setSyncing() {
    const c = this.transitionController()
    if (!c) return
    this.ensureSettledListenerAttached()
    this._shimmerOnSettle = true
    // Idempotent: if already in syncing state, leave shimmer/scramble alone.
    // Subsequent cable-activity events during the same pulse just re-arm
    // the PULSE_MS timer in onActivity — the visible state doesn't churn.
    if (this.currentValue() === this.wordFor("syncing")) return
    // Forward path: shimmer off first, color/value drive the scramble,
    // shimmer flips on once the scramble settles (via _shimmerOnSettle flag).
    c.setShimmer(false)
    c.setColor("accent")
    c.setValue(this.wordFor("syncing"))
  }

  setSynced() {
    const c = this.transitionController()
    if (!c) return
    // Disarm the deferred shimmer-on BEFORE the reverse scramble starts.
    // Without this, a stale settled event from a prior setSyncing would
    // turn shimmer back on right after the syncing→synced scramble finishes.
    this._shimmerOnSettle = false
    // Idempotent: if already in synced state, just ensure shimmer is off.
    if (this.currentValue() === this.wordFor("synced")) {
      c.setShimmer(false)
      return
    }
    c.setShimmer(false)
    c.setColor("muted")
    c.setValue(this.wordFor("synced"))
  }

  setDisconnected() {
    const c = this.transitionController()
    if (!c) return
    this._shimmerOnSettle = false
    if (this.currentValue() === this.wordFor("disconnected")) {
      c.setShimmer(false)
      return
    }
    c.setShimmer(false)
    c.setColor("danger")
    c.setValue(this.wordFor("disconnected"))
  }

  // ─── helpers ──────────────────────────────────────────────────────
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
    if (stateName === "synced")       return this.syncedValue
    if (stateName === "syncing")      return this.syncingValue
    if (stateName === "disconnected") return this.disconnectedValue
    return stateName
  }
}
