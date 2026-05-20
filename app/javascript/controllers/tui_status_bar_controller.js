import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Beta 4 — Phase F1 Lane C. Live data wiring for
// `Tui::TopStatusBarComponent` (Lane B). Subscribes to the
// `StatusBarChannel` (Lane A — broadcasting `pito:status_bar`) and
// patches the marked DOM cells in place. Also ticks a 1Hz local
// wall-clock so the right-most segment always reads true time —
// independent of the cable being connected.
//
// Targets mirror Lane B's `data-tui-status-bar-target="..."` attrs:
//
//   root, sync, syncDot, syncWord, syncTarget,
//   progressBar, progressCounter,
//   sidekiq, sidekiqBusy, sidekiqEnqueued, sidekiqRetry,
//   clock
//
// Payload envelope follows ADR 0017:
//
//   { kind: "<state>", payload: { ... }, ts: "<iso-8601>" }
//
// `kind` ∈ { idle, indeterminate, progress, complete, error, data }.
// `data` is used for Sidekiq queue-depth pushes (no state change).
//
// CSS modifier classes mirror Lane B's component exactly:
//
//   .sb-sync-dot--green / --amber / --red
//   .sb-sync-word--idle / --syncing / --disconnected
//
// The dot color follows sync state (green idle, amber syncing,
// red disconnected). The word follows the same state taxonomy but
// with the human label `synced` / `syncing` / `disconnected`.
//
// Cable lifecycle: connect() creates the consumer + subscription;
// disconnect() unsubscribes AND disconnects the consumer so a Turbo
// morph doesn't leak listeners. Both refs are cached on `this` so
// the teardown is symmetric with `stack_stats_live_controller.js`.
export default class extends Controller {
  static targets = [
    "root",
    "section",
    "sync",
    "syncDot",
    "syncWord",
    "syncTarget",
    "progressBar",
    "progressCounter",
    "sidekiq",
    "sidekiqBusy",
    "sidekiqEnqueued",
    "sidekiqRetry",
    "clock"
  ]

  connect() {
    this.startClock()
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "StatusBarChannel" },
      {
        connected: () => this.onConnected(),
        disconnected: () => this.onDisconnected(),
        received: (data) => this.applyPayload(data)
      }
    )

    // FB-47 (2026-05-20) — TSB breadcrumb tracks the focused panel's
    // title instead of the static section name. The `tui-cursor`
    // controller broadcasts `tui:panel-focus-changed` on every focus
    // move; we patch the `.sb-section` text in place. The SSR-rendered
    // section name remains as the fallback (still visible until the
    // first focus event fires).
    this.boundPanelFocus = this.handlePanelFocus.bind(this)
    document.addEventListener("tui:panel-focus-changed", this.boundPanelFocus)

    // Mitigate the connect-order race: if `tui-cursor` already emitted
    // its initial event before we registered the listener, the focused
    // panel's `data-panel-title` is still readable from the DOM. Seed
    // the section text from it now so the first paint reflects panel
    // focus, not the section name.
    this.seedSectionFromFocusedPanel()
  }

  disconnect() {
    this.stopClock()
    if (this.boundPanelFocus) {
      document.removeEventListener("tui:panel-focus-changed", this.boundPanelFocus)
      this.boundPanelFocus = null
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
  }

  // ---------- Panel focus → breadcrumb ----------

  // FB-101 (2026-05-20) — when a sub-panel inside the focused panel
  // becomes the active L2 cursor target, the breadcrumb renders
  // `<panel>:(<sub-panel>)` where the panel name + parens render in
  // a muted variant of the section accent and the sub-panel name in
  // the full section accent. Without a sub-panel, the breadcrumb
  // remains the bare panel title (FB-47 baseline).
  handlePanelFocus(event) {
    if (!this.hasSectionTarget) return
    const detail = event?.detail || {}
    const panel = detail.panel ?? detail.title ?? ""
    const subPanel = detail.subPanel || null
    if (!panel) return
    this.renderSectionBreadcrumb(panel, subPanel)
  }

  seedSectionFromFocusedPanel() {
    if (!this.hasSectionTarget) return
    const focused = document.querySelector(
      '[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]'
    )
    const title = focused?.dataset?.panelTitle
    if (!title) return
    const subFocused = focused.querySelector(
      '[data-tui-cursor-target="sub-panel"][data-tui-cursor-sub-panel-focused="yes"]'
    )
    const subTitle = subFocused?.dataset?.panelTitle || null
    this.renderSectionBreadcrumb(title, subTitle)
  }

  // Rebuild .sb-section's children. When subPanel is null we render a
  // single text-node (matches the original SSR shape so CSS that targets
  // `.sb-section` keeps working). When subPanel is set we emit the
  // three colored spans that drive FB-101's `stack:(Redis)` shape.
  renderSectionBreadcrumb(panel, subPanel) {
    const el = this.sectionTarget
    while (el.firstChild) el.removeChild(el.firstChild)
    if (!subPanel) {
      el.appendChild(document.createTextNode(panel))
      return
    }
    const panelSpan = document.createElement("span")
    panelSpan.className = "sb-section__panel"
    panelSpan.textContent = panel
    const parenOpen = document.createElement("span")
    parenOpen.className = "sb-section__sub-panel-paren"
    parenOpen.textContent = ":("
    const subSpan = document.createElement("span")
    subSpan.className = "sb-section__sub-panel"
    subSpan.textContent = subPanel
    const parenClose = document.createElement("span")
    parenClose.className = "sb-section__sub-panel-paren"
    parenClose.textContent = ")"
    el.appendChild(panelSpan)
    el.appendChild(parenOpen)
    el.appendChild(subSpan)
    el.appendChild(parenClose)
  }

  // ---------- Clock ----------

  startClock() {
    this.updateClock()
    this.clockTimer = setInterval(() => this.updateClock(), 1000)
  }

  stopClock() {
    if (this.clockTimer) {
      clearInterval(this.clockTimer)
      this.clockTimer = null
    }
  }

  updateClock() {
    if (!this.hasClockTarget) return
    const now = new Date()
    const weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][now.getDay()]
    const month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][now.getMonth()]
    const day = now.getDate()
    const hh = String(now.getHours()).padStart(2, "0")
    const mm = String(now.getMinutes()).padStart(2, "0")
    const ss = String(now.getSeconds()).padStart(2, "0")
    this.clockTarget.textContent = `${weekday}, ${month} ${day} · ${hh}:${mm}:${ss}`
  }

  // ---------- Cable lifecycle callbacks ----------

  onConnected() {
    // Cable established — snap the dot back to the idle (green) state.
    // First real payload from the server will overwrite this immediately
    // if anything is actually in flight.
    this.setSyncState("idle")
  }

  onDisconnected() {
    // Cable dropped — surface the red ✗ disconnected indicator per
    // ADR 0017's error-handling section.
    this.setSyncState("disconnected")
  }

  // ---------- Payload funnel ----------

  applyPayload(data) {
    if (!data) return
    const { kind, payload } = data
    switch (kind) {
      case "idle":
        this.setSyncState("idle")
        this.hideProgressBar()
        break
      case "indeterminate":
        this.setSyncState("syncing", payload && payload.label)
        this.hideProgressBar()
        break
      case "progress":
        this.setSyncState("syncing", payload && payload.label)
        if (payload) this.showProgressBar(payload.current, payload.total)
        break
      case "complete":
        this.setSyncState("idle")
        this.hideProgressBar()
        break
      case "error":
        this.setSyncState("disconnected")
        this.hideProgressBar()
        break
      case "data":
        // Sidekiq queue-depth push — no state change. Payload carries
        // the latest counts (busy / enqueued / retry / scheduled).
        if (payload) this.updateSidekiqStats(payload)
        break
    }
  }

  // ---------- Sync state ----------

  // `state` is the LOCAL three-state taxonomy used by the controller:
  //   idle          → ● green + word "synced"
  //   syncing       → ● amber + word "syncing" (+ optional target label)
  //   disconnected  → ✗ red   + word "disconnected"
  //
  // Lane B's component emits one of four Ruby states (idle / syncing /
  // syncing_with_target / disconnected); the controller collapses the
  // two `syncing*` variants because the only difference is whether the
  // optional `syncTarget` slot has text.
  setSyncState(state, target = null) {
    // Reset every state-flavored modifier on the dot + word so a
    // transition (idle → syncing → idle) doesn't leave a stale class.
    if (this.hasSyncDotTarget) {
      this.syncDotTarget.classList.remove(
        "sb-sync-dot--green",
        "sb-sync-dot--amber",
        "sb-sync-dot--red"
      )
    }
    if (this.hasSyncWordTarget) {
      this.syncWordTarget.classList.remove(
        "sb-sync-word--idle",
        "sb-sync-word--syncing",
        "sb-sync-word--disconnected"
      )
    }

    const dotClass = {
      idle: "sb-sync-dot--green",
      syncing: "sb-sync-dot--amber",
      disconnected: "sb-sync-dot--red"
    }[state] || "sb-sync-dot--green"

    const wordClass = {
      idle: "sb-sync-word--idle",
      syncing: "sb-sync-word--syncing",
      disconnected: "sb-sync-word--disconnected"
    }[state] || "sb-sync-word--idle"

    const wordText = {
      idle: "synced",
      syncing: "syncing",
      disconnected: "disconnected"
    }[state] || "synced"

    const dotGlyph = state === "disconnected" ? "✗" : "●"

    if (this.hasSyncDotTarget) {
      this.syncDotTarget.classList.add(dotClass)
      this.syncDotTarget.textContent = dotGlyph
    }
    if (this.hasSyncWordTarget) {
      this.syncWordTarget.classList.add(wordClass)
      this.syncWordTarget.textContent = wordText
    }
    if (this.hasSyncTargetTarget) {
      // Show / clear the optional `syncing channels`-style label.
      this.syncTargetTarget.textContent = (state === "syncing" && target) ? target : ""
    }
  }

  // ---------- Progress bar ----------

  // Matches Lane B's `PROGRESS_BAR_WIDTH = 8` constant. Centralized
  // here so a future width change only has to touch the component +
  // this single literal (no other consumer of the bar exists).
  static PROGRESS_BAR_WIDTH = 8

  showProgressBar(current, total) {
    if (!this.hasProgressBarTarget || !this.hasProgressCounterTarget) return
    if (current == null || total == null) return
    const totalInt = Number(total)
    const currentInt = Number(current)
    if (!Number.isFinite(totalInt) || totalInt <= 0) return

    const width = this.constructor.PROGRESS_BAR_WIDTH
    const ratio = Math.max(0, Math.min(1, currentInt / totalInt))
    const filled = Math.round(ratio * width)
    const empty = width - filled

    // Lane B splits the bar into two spans (`.sb-progress-bar-filled` +
    // `.sb-progress-bar-empty`) so the filled/empty halves can be colored
    // independently. Rebuild both via DOM APIs (no innerHTML) so the cell
    // stays safe even if a future caller threads user-supplied text in.
    while (this.progressBarTarget.firstChild) {
      this.progressBarTarget.removeChild(this.progressBarTarget.firstChild)
    }
    const filledSpan = document.createElement("span")
    filledSpan.className = "sb-progress-bar-filled"
    filledSpan.textContent = "▓".repeat(filled)
    const emptySpan = document.createElement("span")
    emptySpan.className = "sb-progress-bar-empty"
    emptySpan.textContent = "░".repeat(empty)
    this.progressBarTarget.appendChild(filledSpan)
    this.progressBarTarget.appendChild(emptySpan)

    this.progressCounterTarget.textContent = `${currentInt}/${totalInt}`
  }

  hideProgressBar() {
    if (this.hasProgressBarTarget) this.progressBarTarget.textContent = ""
    if (this.hasProgressCounterTarget) this.progressCounterTarget.textContent = ""
  }

  // ---------- Sidekiq queue-depth cells ----------

  // Payload shape (per ADR 0017):
  //   { busy: <int>, enqueued: <int>, retry: <int>, scheduled: <int> }
  //
  // The bar renders three of the four — b / e / r — so `scheduled` is
  // accepted but not painted here. The `scheduled` slot is a future
  // surface (likely the per-subsystem stack panel).
  updateSidekiqStats(stats) {
    if (stats.busy !== undefined && this.hasSidekiqBusyTarget) {
      this.updateSidekiqCell(this.sidekiqBusyTarget, "b", stats.busy, "sk-b")
    }
    if (stats.enqueued !== undefined && this.hasSidekiqEnqueuedTarget) {
      this.updateSidekiqCell(this.sidekiqEnqueuedTarget, "e", stats.enqueued, "sk-e")
    }
    if (stats.retry !== undefined && this.hasSidekiqRetryTarget) {
      this.updateSidekiqCell(this.sidekiqRetryTarget, "r", stats.retry, "sk-r")
    }
  }

  updateSidekiqCell(el, letter, value, nonZeroClass) {
    if (!el) return
    const n = Number(value)
    const safe = Number.isFinite(n) ? n : 0
    el.textContent = `${letter}${safe}`
    // Mirror Lane B's class swap: `sk-zero` (muted) at 0, per-letter
    // color (`sk-b` / `sk-e` / `sk-r`) when non-zero.
    if (safe === 0) {
      el.classList.add("sk-zero")
      el.classList.remove(nonZeroClass)
    } else {
      el.classList.remove("sk-zero")
      el.classList.add(nonZeroClass)
    }
  }
}
