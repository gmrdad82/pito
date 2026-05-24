import { Controller } from "@hotwired/stimulus"

/**
 * tui-sync-indicator — thin controller for Tui::SyncIndicatorComponent.
 *
 * 2026-05-25 (sync-rebuild) — every `localStorage.setItem` /
 * `localStorage.getItem` call has been deleted. The server's
 * AppSetting rows are the single source of truth; the SyncStateChannel
 * cable broadcasts re-paint every connected client in lockstep.
 *
 * ## Mode values (declared via `data-tui-sync-indicator-mode-value`)
 *
 *   :tst    — aggregate read-only (default; used in the top status bar)
 *   :target — interactive per-panel / per-sub-panel; click POSTs
 *             `/sync/toggle?target=<target>`; the server cascades the
 *             write and broadcasts the new state.
 *
 * ## Five states (locked 2026-05-24)
 *
 *   idle         → "[ ] sync"  accent, no shimmer (target disabled)
 *   active       → "[x] sync"  accent, no shimmer (target enabled)
 *   syncing      → "[x] sync"  accent, shimmer (cable activity)
 *   mixed        → "[-] sync"  accent, no shimmer (parent only —
 *                              children have mixed enabled flags)
 *   disconnected → "[!] sync"  danger (red), no shimmer
 *
 * ## Wire shape
 *
 *   POST /sync/toggle?target=<target> (with CSRF token) → 204 no_content
 *
 *   Then the server broadcasts ONE envelope per cascaded target on the
 *   `pito:sync_state` channel:
 *
 *     { kind: "sync_state",
 *       payload: { target: "<key>", enabled: bool },
 *       ts: "..." }
 *
 *   The shared SyncState bridge (`document` event `tui:sync-changed`,
 *   fan-out from the global subscription) is what every per-target
 *   controller listens to. We do NOT re-implement state caching here.
 *
 * ## :target mode click behavior
 *
 *   - `toggle()` POSTs to `/sync/toggle` and returns. NO local write,
 *     NO optimistic paint. The cable broadcast (which lands in
 *     milliseconds on localhost) drives the repaint via the
 *     `tui:sync-changed` document event.
 *
 * ## :tst mode behavior
 *
 *   - Listens for `tui:sync-changed` (target === "app") to flip
 *     between active and idle.
 *   - Listens for `tui:cable-activity` (Sidekiq stats); shimmer driven
 *     by busy>0 || enqueued>0 || retry>0.
 *   - Click is a no-op in :tst mode.
 */
export default class extends Controller {
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

  // 2026-05-24 — known sub-panel suffixes for each parent panel. Used
  // by the parent's `_isParent()` / `_hasMixedChildren()` derivation
  // so the parent's glyph re-aggregates when a child broadcast lands.
  // Mirror of `Pito::SyncTargets::PARENTS_TO_CHILDREN`.
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
    this._coolDownTimer = null
    this._cableDisconnected = false
    // Per-target enabled cache, hydrated from the SSR class on the
    // host element and updated on every cable broadcast we observe.
    // No localStorage reads anywhere. The cache lets parent VCs
    // re-derive their :mixed state from the latest children states
    // without re-fetching from the server.
    this._enabledByTarget = window.__pitoSyncStateCache = window.__pitoSyncStateCache || {}
    if (this.isTargetMode()) {
      // Seed cache from the SSR state (class `is-accent` is paired with
      // [x] = enabled in our `_paint`). Cheap, idempotent.
      const hostSaysEnabled = this.element.textContent.includes("[x]") ||
                              this.element.textContent.includes("[-]")
      if (this.hasTargetValue && this._enabledByTarget[this.targetValue] === undefined) {
        this._enabledByTarget[this.targetValue] = hostSaysEnabled
      }
    }

    this._boundSyncChanged = this.onSyncChanged.bind(this)
    this._boundActivity = this.onActivity.bind(this)
    document.addEventListener("tui:sync-changed", this._boundSyncChanged)
    document.addEventListener("tui:cable-activity", this._boundActivity)
  }

  disconnect() {
    document.removeEventListener("tui:sync-changed", this._boundSyncChanged)
    document.removeEventListener("tui:cable-activity", this._boundActivity)
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
  // 2026-05-25 (sync-rebuild) — POST + return. Server cascades the
  // write and broadcasts the new state per cascaded target; the
  // resulting `tui:sync-changed` events re-paint every affected VC.
  toggle(event) {
    if (!this.isTargetMode()) return
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    if (!this.hasTargetValue) return
    const target = this.targetValue
    const csrfMeta = document.querySelector('meta[name="csrf-token"]')
    const headers = { "X-Requested-With": "XMLHttpRequest", "Accept": "application/json" }
    if (csrfMeta) headers["X-CSRF-Token"] = csrfMeta.content
    fetch(`/sync/toggle?target=${encodeURIComponent(target)}`, {
      method: "POST",
      headers,
      credentials: "same-origin"
    })

    // 2026-05-24 (sync-rebuild) — surface a centered TST notice on
    // toggle. The panel title comes from the closest panel's
    // `data-panel-title` attr; the next-enabled value is derived
    // optimistically (we know the toggle direction client-side) so
    // the notice fires immediately and does not wait for the cable
    // round-trip. The glyph repaint still waits for the broadcast.
    const optimisticNextEnabled = !this._cachedEnabled(target)
    const panelTitle = this._closestPanelTitle()
    const message = this._buildNoticeMessage(optimisticNextEnabled, panelTitle)
    if (message) {
      document.dispatchEvent(new CustomEvent("tui:notice", {
        detail: { message, severity: "info" }
      }))
    }
  }

  _cachedEnabled(target) {
    const cached = this._enabledByTarget[target]
    return cached === undefined ? true : cached
  }

  // Walks up from the host element to the nearest panel and reads its
  // `data-panel-title` attr. Returns null when not found.
  _closestPanelTitle() {
    if (!this.element || !this.element.closest) return null
    const panel = this.element.closest('[data-tui-cursor-target="panel"][data-panel-title]')
    if (!panel) return null
    const title = panel.dataset.panelTitle
    return typeof title === "string" && title.length > 0 ? title : null
  }

  // Reads the resolved i18n string for a target toggle out of the
  // `<meta name="pito-notices">` payload. Layer-cake fallback:
  // scoped message → bare message → null.
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

  // Listen for sibling / parent / child / master toggles. The
  // upstream emitter is the sync-state cable bridge (see
  // `pito_actions.js`) — it dispatches one `tui:sync-changed` per
  // cascaded target the server wrote.
  onSyncChanged(event) {
    const changed = event && event.detail && event.detail.target
    if (changed === undefined || changed === null) return
    const nextEnabled = event.detail.enabled
    if (typeof nextEnabled === "boolean") {
      this._enabledByTarget[changed] = nextEnabled
    }
    if (this.isTargetMode()) {
      const isSelf   = changed === this.targetValue
      const isParent = this.hasParentTargetValue && changed === this.parentTargetValue
      const isChild  = this._isParent() &&
        (this.constructor.CHILDREN_BY_PARENT[this.targetValue] || []).includes(changed)
      const isMaster = changed === "app"
      if (isSelf || isParent || isChild || isMaster) {
        this._paint(this._computeTargetState())
      }
    } else if (this.isTstMode()) {
      if (changed === "app") {
        if (nextEnabled === false) {
          this.setIdle()
        } else {
          this.setActive()
        }
      }
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

  // ─── :target mode state computation ───────────────────────────────
  //
  // Parent panels compute `:mixed` when their registered children
  // carry divergent enabled flags. Parent-self flag is authoritative
  // only when children are uniform.
  _computeTargetState() {
    if (this._cableDisconnected) return "disconnected"
    if (this._isParent() && this._hasMixedChildren()) return "mixed"
    const selfEnabled = this._cachedEnabled(this.targetValue)
    if (!selfEnabled) return "idle"
    if (this.hasParentTargetValue && this.parentTargetValue) {
      const parentEnabled = this._cachedEnabled(this.parentTargetValue)
      if (!parentEnabled) return "idle"
    }
    if (!this._cachedEnabled("app")) {
      return "idle"
    }
    return "active"
  }

  _isParent() {
    if (!this.hasTargetValue) return false
    const children = this.constructor.CHILDREN_BY_PARENT[this.targetValue]
    return Array.isArray(children) && children.length > 0
  }

  _hasMixedChildren() {
    if (!this._isParent()) return false
    const children = this.constructor.CHILDREN_BY_PARENT[this.targetValue]
    let sawEnabled = false
    let sawDisabled = false
    for (const childTarget of children) {
      if (this._cachedEnabled(childTarget)) sawEnabled = true
      else                                  sawDisabled = true
      if (sawEnabled && sawDisabled) return true
    }
    return false
  }

  _paint(state) {
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

  wordFor(stateName) {
    if (stateName === "idle")         return this.idleValue
    if (stateName === "active")       return this.activeValue
    if (stateName === "syncing")      return this.syncingValue || this.activeValue
    if (stateName === "mixed")        return this.mixedValue || this.idleValue
    if (stateName === "disconnected") return this.disconnectedValue
    return stateName
  }
}
