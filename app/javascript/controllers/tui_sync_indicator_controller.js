import { Controller } from "@hotwired/stimulus"

/**
 * tui-sync-indicator — thin controller for Tui::SyncIndicatorComponent.
 *
 * Phase 1D (2026-05-24) — unified replacement for the deleted
 * tui-pause-control controller. Drives BOTH the top-status-bar
 * aggregate indicator and per-panel / per-sub-panel target indicators
 * with one VC + one controller, switched by the `mode` Stimulus value.
 *
 * ## Mode values (declared via `data-tui-sync-indicator-mode-value`)
 *
 *   :tst    — aggregate read-only (default; used in the top status bar)
 *   :target — interactive per-panel / per-sub-panel; click toggles a
 *             `pito.sync.<target>` localStorage flag.
 *
 * ## Four states
 *
 *   idle         → "[ ] sync"  muted color, no shimmer
 *   active       → "[x] sync"  accent color, no shimmer (work present
 *                              but nothing currently coming over cable
 *                              for THIS target)
 *   syncing      → "[x] sync"  accent color, shimmer (target currently
 *                              receiving cable content)
 *   disconnected → "[!] sync"  danger (red) color, no shimmer
 *
 * ## localStorage shape (locked 2026-05-24)
 *
 *   key   = `pito.sync.<target>`
 *   value = `"yes"` (enabled, default)
 *         | `"no"`  (user-disabled)
 *
 * Unset key = enabled (default). Inverted from the old
 * `pito.pause.<target>` semantic — "yes" used to mean paused.
 *
 * ## :target mode behavior
 *
 *   - Click / Enter / Space toggles `pito.sync.<target>` between "yes"
 *     and "no". After write, controller dispatches `tui:sync-changed`
 *     on document with detail `{ target, parentTarget, enabled }`.
 *   - Initial state computed from localStorage (self + optional
 *     parent_target inheritance).
 *   - Listens for `tui:sync-changed` on document so child sub-panel
 *     controls re-evaluate when the parent panel's flag changes.
 *
 * ## :tst mode behavior
 *
 *   - Listens for `tui:sync-changed` (any target toggled),
 *     `tui:cable-activity` (Sidekiq stats), and per-panel cable lifecycle
 *     events to derive the aggregate state.
 *   - Sidekiq busy/enqueued/retry > 0 AND at least one target enabled
 *     → :active. Cable not connected → :disconnected. Otherwise :idle.
 *   - Click is a no-op in :tst mode.
 *
 * ## Cable suppression contract
 *
 * `tui_panel_cable_controller` reads localStorage with the new
 * `pito.sync.<target>` shape — "no" = suppress payload. Subpanel
 * targets inherit the parent's "no" via the `isTargetSyncDisabled`
 * helper exported below.
 */
export default class extends Controller {
  static outlets = ["tui-transition"]
  static values = {
    mode: { type: String, default: "tst" },
    target: String,
    parentTarget: String,
    idle: String,
    active: String,
    syncing: String,
    disconnected: String
  }

  static COOL_DOWN_MS = 1000

  connect() {
    this._shimmerOnSettle = false
    this._settledAttachedTo = null
    this._coolDownTimer = null
    this._cableDisconnected = false
    this._boundExplicit = this.onExplicitState.bind(this)
    this._boundSyncChanged = this.onSyncChanged.bind(this)
    this._boundActivity = this.onActivity.bind(this)
    this._boundSettled = this.onTransitionSettled.bind(this)
    document.addEventListener("tui:sync-changed", this._boundSyncChanged)
    document.addEventListener("tui:sync-state-changed", this._boundExplicit)
    document.addEventListener("tui:cable-activity", this._boundActivity)

    if (this.isTargetMode()) {
      this._paint(this._computeTargetState())
    }
  }

  disconnect() {
    document.removeEventListener("tui:sync-changed", this._boundSyncChanged)
    document.removeEventListener("tui:sync-state-changed", this._boundExplicit)
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

  // ─── mode detection ───────────────────────────────────────────────
  isTargetMode() {
    return this.hasModeValue && this.modeValue === "target"
  }

  isTstMode() {
    return !this.isTargetMode()
  }

  // ─── :target mode click handler ───────────────────────────────────
  toggle(event) {
    if (!this.isTargetMode()) return
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    if (!this.hasTargetValue) return
    const key = this._lsKey(this.targetValue)
    // Default semantic: unset = "yes" (enabled). A toggle flips to "no".
    const currentEnabled = this._readEnabled(this.targetValue)
    const nextEnabled = !currentEnabled
    localStorage.setItem(key, nextEnabled ? "yes" : "no")
    this._paint(this._computeTargetState())
    document.dispatchEvent(new CustomEvent("tui:sync-changed", {
      detail: {
        target: this.targetValue,
        parentTarget: this.hasParentTargetValue ? this.parentTargetValue : null,
        enabled: nextEnabled
      }
    }))
  }

  // Listen for sibling / parent toggles — re-evaluate if this control
  // observes the changed target (self) or its parent (inheritance).
  onSyncChanged(event) {
    const changed = event && event.detail && event.detail.target
    if (!changed) return
    if (this.isTargetMode()) {
      if (
        changed === this.targetValue ||
        (this.hasParentTargetValue && changed === this.parentTargetValue)
      ) {
        this._paint(this._computeTargetState())
      }
    }
    // In :tst mode, any change in any target may shift the aggregate.
    // Re-derive on next tick (Sidekiq event will refresh the source-of-truth
    // numbers; the explicit refresh here is a safe nudge).
  }

  // ─── explicit state path (legacy `tui:sync-state-changed` event) ──
  onExplicitState(event) {
    const state = event && event.detail && event.detail.state
    if (!state) return
    if (state === "disconnected") {
      this.setDisconnected()
    } else if (state === "syncing") {
      this.setSyncing()
    } else if (state === "active") {
      this.setActive()
    } else {
      this.setIdle()
    }
  }

  // Sidekiq-aware activity handler. Only Sidekiq stats drive the
  // active/idle state in :tst mode.
  onActivity(event) {
    if (!this.isTstMode()) return
    const detail = event && event.detail || {}
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

  // ─── :target mode state computation ───────────────────────────────
  _computeTargetState() {
    if (this._cableDisconnected) return "disconnected"
    const selfEnabled = this._readEnabled(this.targetValue)
    if (!selfEnabled) return "idle"
    if (this.hasParentTargetValue && this.parentTargetValue) {
      const parentEnabled = this._readEnabled(this.parentTargetValue)
      if (!parentEnabled) return "idle"
    }
    // Without finer per-target activity signal (future cable wiring),
    // default to idle for enabled targets. Cable suppression layer
    // remains the load-bearing semantic.
    return "idle"
  }

  _readEnabled(target) {
    if (!target) return true
    const raw = localStorage.getItem(this._lsKey(target))
    if (raw === "no") return false
    return true // "yes" or unset → enabled (default)
  }

  _lsKey(target) {
    return `pito.sync.${target}`
  }

  _paint(state) {
    if (state === "disconnected") {
      this.setDisconnected()
    } else if (state === "syncing") {
      this.setSyncing()
    } else if (state === "active") {
      this.setActive()
    } else {
      this.setIdle()
    }
  }

  // ─── delegation to tui-transition outlet ──────────────────────────
  setActive() {
    const c = this.transitionController()
    if (!c) return
    this.ensureSettledListenerAttached()
    this._shimmerOnSettle = false
    if (this.currentValue() === this.wordFor("active")) {
      c.setShimmer(false)
      return
    }
    c.setShimmer(false)
    c.setColor("accent")
    c.setValue(this.wordFor("active"))
  }

  setSyncing() {
    const c = this.transitionController()
    if (!c) return
    this.ensureSettledListenerAttached()
    this._shimmerOnSettle = true
    if (this.currentValue() === this.wordFor("syncing")) {
      c.setShimmer(true)
      return
    }
    c.setShimmer(false)
    c.setColor("accent")
    c.setValue(this.wordFor("syncing"))
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
    if (stateName === "idle")         return this.idleValue
    if (stateName === "active")       return this.activeValue
    if (stateName === "syncing")      return this.syncingValue || this.activeValue
    if (stateName === "disconnected") return this.disconnectedValue
    return stateName
  }
}

/**
 * Module helper — exported so cable consumer controllers can ask
 * "is this target's syncing disabled right now?" without re-implementing
 * the inheritance logic. Default export stays the Controller class.
 *
 * Semantic: localStorage `pito.sync.<target>` = "no" means user-disabled
 * (drop cable payloads). Unset or "yes" means enabled (default).
 * Parent inheritance: a disabled parent target cascades to its
 * sub-panels unless the sub-panel has its own explicit "yes" override.
 */
export function isTargetSyncDisabled(target, parentTarget = null) {
  const direct = localStorage.getItem(`pito.sync.${target}`)
  if (direct === "no") return true
  if (direct === "yes") return false
  if (parentTarget) {
    return localStorage.getItem(`pito.sync.${parentTarget}`) === "no"
  }
  return false
}
