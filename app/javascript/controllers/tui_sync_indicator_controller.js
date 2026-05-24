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
 * ## Five states
 *
 *   idle         → "[ ] sync"  accent color, no shimmer ("actions are
 *                              always accent" lock 2026-05-24 — idle
 *                              promoted from muted to accent)
 *   active       → "[x] sync"  accent color, no shimmer (work present
 *                              but nothing currently coming over cable
 *                              for THIS target)
 *   syncing      → "[x] sync"  accent color, shimmer (target currently
 *                              receiving cable content)
 *   mixed        → "[-] sync"  accent color, no shimmer (parent panel
 *                              only — sub-panels have mixed self-flags;
 *                              clicking the parent bulk-writes children
 *                              to a uniform state, see toggle())
 *   disconnected → "[!] sync"  danger (red) color, no shimmer
 *
 * ## localStorage shape (locked 2026-05-24, refined sync-rebuild)
 *
 *   key   = `pito.sync.app`                           — MASTER
 *         | `pito.sync.<screen>.<panel>`              — per-panel
 *         | `pito.sync.<screen>.<panel>.<sub_panel>`  — per-sub-panel
 *   value = `"yes"` (enabled, default)
 *         | `"no"`  (user-disabled)
 *
 * Unset key = enabled (default). `pito.sync.app` is the ONE global
 * master across every screen — toggling it suppresses every panel's
 * cable broadcasts unless that panel has an explicit `"yes"` override.
 * Per-panel-per-screen flags are independent across screens.
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
    mixed: String,
    disconnected: String
  }

  // 2026-05-24 — known sub-panel suffixes for each parent panel. The
  // `toggle()` handler walks this table to (a) bulk-write children when
  // a parent is toggled and (b) re-aggregate parent state when a child
  // changes. Keep in sync with the `Pito::Stack::*SubPanelComponent`
  // target string in each sub-panel template.
  static CHILDREN_BY_PARENT = {
    "home.stack": [
      "home.stack.meilisearch",
      "home.stack.voyage",
      "home.stack.postgres",
      "home.stack.assets"
    ]
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
  //
  // 2026-05-24 — parent → child propagation. When the toggled target is
  // a PARENT (its key appears in CHILDREN_BY_PARENT), the new state is
  // also written to every child target's localStorage key. The result:
  // a parent toggle aligns all its children, so the user can pause an
  // entire panel's sync without per-sub-panel clicks. Children remain
  // independently toggleable; the parent's mixed-state read kicks in
  // automatically when a child diverges.
  toggle(event) {
    if (!this.isTargetMode()) return
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    if (!this.hasTargetValue) return
    const key = this._lsKey(this.targetValue)
    // Default semantic: unset = "yes" (enabled). A toggle flips to "no".
    // From the `:mixed` state, treat the click as "uniformly disable" so
    // the cascade lands on a single coherent state (matches user mental
    // model: tap once to silence the panel).
    const wasMixed = this._isParent() && this._hasMixedChildren()
    const currentEnabled = wasMixed ? true : this._readEnabled(this.targetValue)
    const nextEnabled = !currentEnabled
    localStorage.setItem(key, nextEnabled ? "yes" : "no")

    // Parent → children bulk write. Iterate through registered children
    // and align them on the new flag. Each child's controller re-paints
    // via the `tui:sync-changed` listener below.
    const children = this.constructor.CHILDREN_BY_PARENT[this.targetValue] || []
    children.forEach((childTarget) => {
      localStorage.setItem(this._lsKey(childTarget), nextEnabled ? "yes" : "no")
      document.dispatchEvent(new CustomEvent("tui:sync-changed", {
        detail: { target: childTarget, parentTarget: this.targetValue, enabled: nextEnabled }
      }))
    })

    this._paint(this._computeTargetState())
    document.dispatchEvent(new CustomEvent("tui:sync-changed", {
      detail: {
        target: this.targetValue,
        parentTarget: this.hasParentTargetValue ? this.parentTargetValue : null,
        enabled: nextEnabled
      }
    }))

    // 2026-05-24 (sync-rebuild) — surface a centered TST notice so the
    // user gets immediate visual feedback on the silent toggle. The
    // panel title comes from the closest panel's `data-panel-title`
    // attribute. When unavailable, fall back to the bare master copy.
    const panelTitle = this._closestPanelTitle()
    const message = this._buildNoticeMessage(nextEnabled, panelTitle)
    if (message) {
      document.dispatchEvent(new CustomEvent("tui:notice", {
        detail: { message, severity: "info" }
      }))
    }
  }

  // Walks up from the host element to the nearest panel and reads its
  // `data-panel-title` attribute (planted by `Tui::PanelBase`). Falls
  // back to null when not found — caller emits the title-less message.
  _closestPanelTitle() {
    if (!this.element || !this.element.closest) return null
    const panel = this.element.closest('[data-tui-cursor-target="panel"][data-panel-title]')
    if (!panel) return null
    const title = panel.dataset.panelTitle
    return typeof title === "string" && title.length > 0 ? title : null
  }

  // Reads the resolved i18n string for a target toggle out of the
  // `<meta name="pito-notices" content="JSON">` payload. Layer-cake
  // fallback: scoped message → bare message → null. Caller decides
  // whether to emit the event.
  _buildNoticeMessage(nextEnabled, panelTitle) {
    const meta = document.querySelector('meta[name="pito-notices"]')
    if (!meta) return null
    let map
    try { map = JSON.parse(meta.content) } catch (_) { return null }
    if (!map || typeof map !== "object") return null
    if (panelTitle) {
      const tmpl = nextEnabled ? map.sync_resumed_for : map.sync_paused_for
      if (typeof tmpl === "string" && tmpl.length > 0) {
        return tmpl.replace(/%\{title\}/g, panelTitle)
      }
    }
    const bare = nextEnabled ? map.sync_resumed : map.sync_paused
    return typeof bare === "string" && bare.length > 0 ? bare : null
  }

  // Listen for sibling / parent / child / master toggles — re-evaluate
  // if this control observes the changed target (self), its parent
  // (inheritance), one of its registered children (parent ↔ child
  // mixed-state aggregation), or the global `app` master switch (cascades
  // to every target on every screen). All locked 2026-05-24.
  onSyncChanged(event) {
    const changed = event && event.detail && event.detail.target
    if (!changed) return
    if (this.isTargetMode()) {
      const isSelf   = changed === this.targetValue
      const isParent = this.hasParentTargetValue && changed === this.parentTargetValue
      // 2026-05-24 — child→parent aggregation. When ANY registered child
      // changes, the parent re-derives its mixed/idle reading.
      const isChild  = this._isParent() &&
        (this.constructor.CHILDREN_BY_PARENT[this.targetValue] || []).includes(changed)
      // 2026-05-24 (sync-rebuild) — global `app` master cascade. Affects
      // every per-panel target on every screen.
      const isMaster = changed === "app"
      if (isSelf || isParent || isChild || isMaster) {
        this._paint(this._computeTargetState())
      }
    } else if (this.isTstMode()) {
      // 2026-05-24 (sync-rebuild) — TST `:tst` mode mirrors the master
      // `app` switch. When the user fires `Space s`, the TST glyph
      // flips between idle/`[ ]` (master OFF) and the Sidekiq-derived
      // active/idle state (master ON).
      if (changed === "app") {
        if (event.detail.enabled === false) {
          this.setIdle()
        }
        // When master flips back ON, the next Sidekiq tick re-derives
        // active/idle from the live stats. The explicit nudge here is
        // not needed.
      }
    }
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
    } else if (state === "mixed") {
      this.setMixed()
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
  //
  // 2026-05-24 — parent panels compute `:mixed` when their registered
  // children carry divergent self-flags. The mixed render uses `[-]` +
  // accent (no shimmer) and signals to the user that some — but not
  // all — sub-panels are silenced. Parent-self flag is treated as
  // authoritative only when children are uniform.
  _computeTargetState() {
    if (this._cableDisconnected) return "disconnected"
    if (this._isParent() && this._hasMixedChildren()) return "mixed"
    const selfEnabled = this._readEnabled(this.targetValue)
    if (!selfEnabled) return "idle"
    if (this.hasParentTargetValue && this.parentTargetValue) {
      const parentEnabled = this._readEnabled(this.parentTargetValue)
      if (!parentEnabled) return "idle"
    }
    // 2026-05-24 (sync-rebuild) — global `app` master switch cascade.
    // When `pito.sync.app` is "no", every per-panel target on every
    // screen paints as idle UNLESS the panel's direct flag is explicitly
    // "yes" (user opt-in per panel survives the global master OFF).
    if (
      localStorage.getItem(this._lsKey("app")) === "no" &&
      localStorage.getItem(this._lsKey(this.targetValue)) !== "yes"
    ) {
      return "idle"
    }
    // 2026-05-25 — bug fix: enabled target with no early-exit hit must
    // render as `:active` (`[x] sync`), NOT `:idle`. The previous final
    // fallback returned `"idle"` and the toggle never flipped the glyph
    // from `[ ]` to `[x]` after enabling. State semantics (locked):
    //   `[ ]` idle    = user-disabled / parent-disabled / master-disabled
    //                   (without explicit per-target opt-in)
    //   `[x]` active  = user-enabled AND no specific cable activity right
    //                   now (default after enabling — what this branch
    //                   returns)
    //   `[x]` syncing = active + shimmer (driven elsewhere by cable
    //                   activity events; not derived here).
    return "active"
  }

  // Returns true when this target has registered children in the
  // CHILDREN_BY_PARENT table (i.e. it is a parent panel).
  _isParent() {
    if (!this.hasTargetValue) return false
    const children = this.constructor.CHILDREN_BY_PARENT[this.targetValue]
    return Array.isArray(children) && children.length > 0
  }

  // Returns true when this parent's registered children have BOTH
  // enabled AND disabled self-flags (mixed). All-yes or all-no = uniform.
  _hasMixedChildren() {
    if (!this._isParent()) return false
    const children = this.constructor.CHILDREN_BY_PARENT[this.targetValue]
    let sawEnabled = false
    let sawDisabled = false
    for (const childTarget of children) {
      if (this._readEnabled(childTarget)) sawEnabled = true
      else                                sawDisabled = true
      if (sawEnabled && sawDisabled) return true
    }
    return false
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
    // 2026-05-25 — STRIPPED. The tui-transition outlet machinery (and
    // its global `.tui-sync-word` selector) was the source of every
    // sync glyph routing bug. Plain textContent swap = instant + can
    // never misroute. Set the host text + color class directly.
    const word = this.wordFor(state) || this.wordFor("idle")
    if (typeof word === "string" && word.length > 0) {
      this.element.textContent = word
    }
    const COLORS = ["is-accent", "is-muted", "is-pink", "is-accent-pale", "is-warn"]
    COLORS.forEach((cls) => this.element.classList.remove(cls))
    if (state === "disconnected") {
      this.element.classList.add("is-pink")
    } else {
      this.element.classList.add("is-accent")
    }
    if (state === "syncing") {
      this.element.classList.add("tui-shimmer")
    } else {
      this.element.classList.remove("tui-shimmer")
    }
  }

  // 2026-05-25 — setX wrappers now route through _paint (the direct
  // textContent swap). The old tui-transition outlet machinery is
  // dead code; kept the method names so existing callers
  // (onActivity, onExplicitState, etc.) still work without rewrite.
  setActive()       { this._paint("active") }
  setSyncing()      { this._paint("syncing") }
  setIdle()         { this._paint("idle") }
  setMixed()        { this._paint("mixed") }
  setDisconnected() { this._paint("disconnected") }

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
    if (stateName === "mixed")        return this.mixedValue || this.idleValue
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
 *
 * 2026-05-24 (sync-rebuild) — `pito.sync.app` global master gate. When
 * the master switch is "no" (toggled via `Space s` →
 * `:toggle_tst_sync`), EVERY per-panel target on EVERY screen is
 * treated as disabled even if its direct flag is unset / "yes". A
 * direct "yes" override still wins (user opt-in per panel survives the
 * global master OFF). The per-panel-per-screen flag namespace
 * (`pito.sync.<screen>.<panel>`) is independent across screens.
 */
export function isTargetSyncDisabled(target, parentTarget = null) {
  const direct = localStorage.getItem(`pito.sync.${target}`)
  if (direct === "no") return true
  if (direct === "yes") return false
  if (parentTarget) {
    if (localStorage.getItem(`pito.sync.${parentTarget}`) === "no") return true
  }
  // 2026-05-24 (sync-rebuild) — global `app` master switch cascade.
  // Applies regardless of screen; the direct-yes override above already
  // covers per-panel opt-ins.
  if (localStorage.getItem("pito.sync.app") === "no") return true
  return false
}
