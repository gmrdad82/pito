import { Controller } from "@hotwired/stimulus"

// Beta 4 — Phase F1 child controller for `Tui::SyncIndicatorComponent`.
//
// 2026-05-22 (activity-pulse refactor) — the sync indicator no longer
// listens for a discrete `sync` payload kind. Instead it listens for
// the generic `tui:cable-activity` event (fanned out by the parent
// `tui-status-bar` controller on EVERY received cable message
// regardless of kind) and flips to the `syncing` glyph for 400ms,
// re-arming the timer on every subsequent activity event. When the
// timer expires the indicator returns to `synced`. This makes the
// indicator a true "any traffic" pulse, trivially extensible as new
// cable kinds are added (no per-kind listener wiring required).
//
// The controller also honors the explicit `tui:sync-changed` event for
// the `disconnected` state ONLY — the cable lifecycle (`connected` /
// `disconnected` callbacks on the parent's ActionCable subscription)
// drives that path. `synced` / `syncing` are owned entirely by the
// activity-pulse mechanism.
//
// Event contracts:
//
//   tui:cable-activity (every cable message)
//     → flip to `syncing` for PULSE_MS, then back to `synced`.
//
//   tui:sync-changed
//     detail: { state: "synced" | "syncing" | "disconnected" }
//     → only `disconnected` is honored here. Synced/syncing pass
//       through the activity-pulse path.
//
// Word labels come from data-* values seeded by the VC (which sources
// them from `config/locales/tui/en.yml` `tui.tst.sync.*`) so the JS
// layer never inlines English strings.
export default class extends Controller {
  static targets = ["dot", "word", "target"]
  static values = {
    synced: String,
    syncing: String,
    disconnected: String
  }

  // Activity pulse duration in milliseconds. Every `tui:cable-activity`
  // event re-arms this timer; the indicator returns to `synced` only
  // after PULSE_MS of quiet.
  static PULSE_MS = 400

  // Glyph + class triples for each state. Class names match the locked
  // CSS in `app/assets/tailwind/application.css`.
  static GLYPH_SYNCING = "●"
  static GLYPH_SYNCED = "●"
  static GLYPH_DISCONNECTED = "✗"

  connect() {
    this.boundActivity = this.onActivity.bind(this)
    this.boundExplicitState = this.onExplicitState.bind(this)
    document.addEventListener("tui:cable-activity", this.boundActivity)
    document.addEventListener("tui:sync-changed", this.boundExplicitState)
    this.pulseTimer = null
    // Initial state — synced (matches SSR first paint).
    this.setState("synced")
  }

  disconnect() {
    if (this.boundActivity) {
      document.removeEventListener("tui:cable-activity", this.boundActivity)
      this.boundActivity = null
    }
    if (this.boundExplicitState) {
      document.removeEventListener("tui:sync-changed", this.boundExplicitState)
      this.boundExplicitState = null
    }
    if (this.pulseTimer) {
      clearTimeout(this.pulseTimer)
      this.pulseTimer = null
    }
  }

  // Activity event — flip to syncing for PULSE_MS, re-arming on every
  // new activity so a burst of traffic keeps the indicator amber until
  // the burst quiets.
  onActivity() {
    this.setState("syncing")
    if (this.pulseTimer) clearTimeout(this.pulseTimer)
    this.pulseTimer = setTimeout(() => {
      this.setState("synced")
      this.pulseTimer = null
    }, this.constructor.PULSE_MS)
  }

  // Explicit state event — only honor `disconnected`. Synced/syncing
  // are owned by the activity-pulse path.
  onExplicitState(event) {
    const state = event?.detail?.state
    if (state === "disconnected") {
      if (this.pulseTimer) {
        clearTimeout(this.pulseTimer)
        this.pulseTimer = null
      }
      this.setState("disconnected")
    }
  }

  setState(state) {
    if (this.hasDotTarget) {
      this.dotTarget.classList.remove(
        "sb-sync-dot--green",
        "sb-sync-dot--amber",
        "sb-sync-dot--red"
      )
    }
    if (this.hasWordTarget) {
      this.wordTarget.classList.remove(
        "sb-sync-word--idle",
        "sb-sync-word--syncing",
        "sb-sync-word--disconnected"
      )
    }

    let dotClass = "sb-sync-dot--green"
    let wordClass = "sb-sync-word--idle"
    let dotGlyph = this.constructor.GLYPH_SYNCED
    let wordText = this.syncedValue

    if (state === "syncing") {
      dotClass = "sb-sync-dot--amber"
      wordClass = "sb-sync-word--syncing"
      dotGlyph = this.constructor.GLYPH_SYNCING
      wordText = this.syncingValue
    } else if (state === "disconnected") {
      dotClass = "sb-sync-dot--red"
      wordClass = "sb-sync-word--disconnected"
      dotGlyph = this.constructor.GLYPH_DISCONNECTED
      wordText = this.disconnectedValue
    }

    if (this.hasDotTarget) {
      this.dotTarget.classList.add(dotClass)
      this.dotTarget.textContent = dotGlyph
    }
    if (this.hasWordTarget) {
      this.wordTarget.classList.add(wordClass)
      this.wordTarget.textContent = wordText
    }
    // The optional `syncing channels`-style target is no longer wired
    // from the activity path (the activity event carries no target
    // label). Clear it so a stale label from a prior explicit dispatch
    // doesn't linger.
    if (this.hasTargetTarget) {
      this.targetTarget.textContent = ""
    }
  }
}
