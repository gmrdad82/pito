import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Beta 4 — Phase F1 Lane C. Live data wiring for
// `Tui::TopStatusBarComponent` (Lane B). Subscribes to the
// `StatusBarChannel` (Lane A — broadcasting `pito:status_bar`) and
// fans out kind-specific custom DOM events to child Stimulus controllers
// (one per ViewComponent slot: SyncIndicator, SidekiqStats, DateTime,
// etc.). The parent owns the cable subscription + breadcrumb + local
// wall-clock; every other slot is painted by its own child controller
// listening for the kind-specific event.
//
// 2026-05-22 (registry refactor) — the previous `switch (kind)` block
// was replaced by a frozen dictionary at module top (`KIND_HANDLERS`).
// Adding a new cable kind = one entry in the map. The same dispatch
// also fires a generic `tui:cable-activity` event on every received
// message so activity-aware listeners (e.g. the sync indicator pulse)
// can react without registering for each individual kind.
//
// Targets (legacy direct-target patches retained for sync/breadcrumb
// only):
//   root, section, clock (legacy clock target unused since the
//   DateTime VC was extracted; kept on the static targets list as a
//   no-op for backward compat).
//
// Payload envelope follows ADR 0017:
//
//   { kind: "<state>", payload: { ... }, ts: "<iso-8601>" }
//
// Canonical kinds (FB-test-infra 2026-05-22):
//
//   sync          → fans out `tui:sync-changed`
//   sidekiq       → fans out `tui:sidekiq-changed`
//   notifications → fans out `tui:notifications-changed`
//   data          → alias of `sidekiq` (legacy Sidekiq middleware envelope)
//
// Legacy long-running-job kinds (idle / indeterminate / progress /
// complete / error) are registered without a kind-specific event —
// they still fire the generic `tui:cable-activity` event so any future
// activity-aware listener can pick them up.

// Cable-kind routing registry. Adding a new cable kind = one entry.
// Each entry declares:
//   - event: the document-level CustomEvent name fanned out for VCs to listen to
//   - payloadKeys: array of expected payload field names (for dev-time validation)
//   - alias: optional — when set, this kind is an alias of the named canonical kind
//
// EVERY received message — regardless of kind — also fires the generic
// `tui:cable-activity` event for activity-aware VCs (e.g. sync indicator).
export const KIND_HANDLERS = Object.freeze({
  sync:          { event: "tui:sync-changed",          payloadKeys: ["state", "target"] },
  sidekiq:       { event: "tui:sidekiq-changed",       payloadKeys: ["busy", "enqueued", "retry"] },
  notifications: { event: "tui:notifications-changed", payloadKeys: ["future_count"] },
  data:          { alias: "sidekiq" },  // legacy Sidekiq middleware kind
  // Legacy long-running-job kinds — fire activity event only, no specific listener:
  idle:          { event: null, payloadKeys: [] },
  indeterminate: { event: null, payloadKeys: [] },
  progress:      { event: null, payloadKeys: [] },
  complete:      { event: null, payloadKeys: [] },
  error:         { event: null, payloadKeys: [] }
})

export const ACTIVITY_EVENT = "tui:cable-activity"

export default class extends Controller {
  static targets = [
    "root",
    "section"
  ]

  // Re-export the registry on the controller class so specs / external
  // consumers can lock the shape without importing the module directly.
  static KIND_HANDLERS = KIND_HANDLERS
  static ACTIVITY_EVENT = ACTIVITY_EVENT

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "StatusBarChannel" },
      {
        connected: () => this.onConnected(),
        disconnected: () => this.onDisconnected(),
        received: (data) => this.received(data)
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

  // ---------- Cable payload funnel (registry-driven) ----------

  // 2026-05-22 — Map-driven dispatch. Every received message fires
  // `tui:cable-activity` first (so activity-aware listeners pulse on
  // any traffic), then resolves the `kind` to its registry entry and
  // fans out the kind-specific event if defined. Aliases are resolved
  // one hop (no recursion needed).
  received(data) {
    const { kind, payload } = data || {}

    // Always fire the generic activity event first — for activity-aware listeners.
    document.dispatchEvent(new CustomEvent(ACTIVITY_EVENT, {
      detail: { kind, payload, ts: data?.ts },
      bubbles: false
    }))

    // Resolve aliases (one hop only).
    let handler = KIND_HANDLERS[kind]
    if (handler && handler.alias) handler = KIND_HANDLERS[handler.alias]
    if (!handler) {
      console.warn(`[tui-status-bar] unknown cable kind: ${kind}`)
      return
    }

    // Fan-out the kind-specific event if defined.
    if (handler.event) {
      document.dispatchEvent(new CustomEvent(handler.event, {
        detail: payload || {},
        bubbles: false
      }))
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

  // ---------- Cable lifecycle callbacks ----------
  //
  // Cable connect / disconnect are signaled out via the same custom
  // event mechanism the registry uses — the SyncIndicator child
  // controller listens for explicit `disconnected` state via
  // `tui:sync-changed` so the dot can flip red without needing a
  // dedicated event channel for cable lifecycle.

  onConnected() {
    // Cable established — re-paint as synced.
    document.dispatchEvent(new CustomEvent("tui:sync-changed", {
      detail: { state: "synced" },
      bubbles: false
    }))
  }

  onDisconnected() {
    // Cable dropped — surface the red ✗ disconnected indicator per
    // ADR 0017's error-handling section.
    document.dispatchEvent(new CustomEvent("tui:sync-changed", {
      detail: { state: "disconnected" },
      bubbles: false
    }))
  }
}
