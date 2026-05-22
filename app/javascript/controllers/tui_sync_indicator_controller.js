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
 *       burst of traffic keeps the cell amber until the burst quiets.
 *
 *   tui:sync-changed
 *     detail: { state: "synced" | "syncing" | "disconnected" }
 *     → explicit state override. `disconnected` cancels any in-flight
 *       activity pulse; `synced` / `syncing` also pass through but are
 *       normally owned by the activity-pulse path.
 *
 * Sequencing rule (shimmer ↔ scramble, never overlap):
 *
 *   forward (synced → syncing):
 *     1. setShimmer(false)          // clear stale shimmer
 *     2. setColor("accent")
 *     3. setValue(word)             // scramble starts
 *     4. on tui-transition:settled → setShimmer(true)
 *
 *   reverse (anything → synced / disconnected):
 *     1. setShimmer(false)          // shimmer off FIRST
 *     2. setColor(...)
 *     3. setValue(word)             // scramble back
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
    this._boundExplicit = this.onExplicitState.bind(this)
    this._boundActivity = this.onActivity.bind(this)
    document.addEventListener("tui:sync-changed", this._boundExplicit)
    document.addEventListener("tui:cable-activity", this._boundActivity)
  }

  disconnect() {
    document.removeEventListener("tui:sync-changed", this._boundExplicit)
    document.removeEventListener("tui:cable-activity", this._boundActivity)
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

  // ─── delegation to tui-transition outlet ──────────────────────────
  setSyncing() {
    const c = this.transitionController()
    if (!c) return
    // forward path: shimmer off first, color/value drive the scramble,
    // shimmer flips on once the scramble settles.
    c.setShimmer(false)
    c.setColor("accent")
    c.setValue(this.wordFor("syncing"))
    c.element.addEventListener(
      "tui-transition:settled",
      () => c.setShimmer(true),
      { once: true }
    )
  }

  setSynced() {
    const c = this.transitionController()
    if (!c) return
    // reverse path: shimmer off FIRST, then scramble back.
    c.setShimmer(false)
    c.setColor("accent")
    c.setValue(this.wordFor("synced"))
  }

  setDisconnected() {
    const c = this.transitionController()
    if (!c) return
    c.setShimmer(false)
    c.setColor("pink")
    c.setValue(this.wordFor("disconnected"))
  }

  // ─── helpers ──────────────────────────────────────────────────────
  transitionController() {
    if (this.hasTuiTransitionOutlet) return this.tuiTransitionOutlet
    return null
  }

  wordFor(stateName) {
    if (stateName === "synced")       return this.syncedValue
    if (stateName === "syncing")      return this.syncingValue
    if (stateName === "disconnected") return this.disconnectedValue
    return stateName
  }
}
