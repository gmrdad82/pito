import { Controller } from "@hotwired/stimulus"

/**
 * tui-sidekiq-stats — listens for tui:sidekiq-changed on document and
 * updates the colocated tui-transition outlet with the formatted
 * single-string value + per-segment colors.
 *
 * Format: "b<short(busy)> e<short(enqueued)> r<short(retry)> d<short(dead)>"
 *
 * Segments JSON (consumed by tui-transition's segmentsValue):
 *   [{ name: "busy",     range: [start, endExclusive], color: <name> },
 *    { name: "enqueued", range: [start, endExclusive], color: <name> },
 *    { name: "retry",    range: [start, endExclusive], color: <name> },
 *    { name: "dead",     range: [start, endExclusive], color: <name> }]
 *
 * Concurrency-aware tiering (mirrors Tui::SidekiqStatsComponent — keep
 * the two in sync if either side changes):
 *
 *   busy
 *     b == 0                          → muted
 *     ratio = busy/concurrency
 *     ratio <= 0.8                    → success
 *     0.8 < ratio < 1.0               → warn
 *     ratio == 1.0 AND enqueued > 0   → danger  (backpressure)
 *     ratio == 1.0 AND enqueued == 0  → warn    (saturated, no queue)
 *
 *   enqueued
 *     e == 0                          → muted
 *     mult = enqueued/concurrency
 *     mult <= 1.0                     → success
 *     1.0 < mult <= 2.0               → warn
 *     mult > 2.0                      → danger
 *
 *   retry → r > 0 danger else muted   (flat)
 *   dead  → d > 0 fatal  else muted   (flat)
 *
 * `dead` reflects Sidekiq's dead set — jobs that exhausted all retry
 * attempts. Surfaced with Dracula red (`--color-fatal`) when > 0;
 * deliberately NOT included in tui-sync-indicator's activity check
 * (terminal failures are not active work).
 *
 * Cascade behavior: length changes in any segment ripple-scramble
 * downstream segments via tui-transition's diff-only animateDiff path.
 *
 * Mount: parent `<span class="tui-sidekiq-stats">` with both
 *   `tui-sidekiq-stats` and `tui-transition` Stimulus controllers, plus
 *   `data-tui-sidekiq-stats-tui-transition-outlet=".tui-sidekiq-stats"`.
 *
 * The JS short-format MUST match `Pito::Formatter::ShortNumber` exactly:
 *
 *   0           → "0"
 *   32          → "32"
 *   999         → "999"
 *   1_000       → "1k"
 *   22_345      → "22k"
 *   899_000     → "899k"
 *   1_000_000   → "1M"
 *   999_999_999 → "999M"
 *   1_000_000_000 → "1B"
 *
 * @contract see app/services/pito/formatter/short_number.rb
 * @contract see app/javascript/controllers/tui_transition_controller.js
 */
export default class extends Controller {
  static outlets = ["tui-transition"]

  // The brand prefix is sourced from i18n on the Ruby side
  // (`tui.sidekiq.label`) and emitted by Tui::SidekiqStatsComponent as a
  // Stimulus value (`data-tui-sidekiq-stats-prefix-value`). The default
  // here is a safety fallback used only when the value is absent (SSR
  // boot ordering, isolated controller tests). The same YAML feeds the
  // future Rust TUI client.
  static values = {
    prefix: { type: String, default: "Sidekiq" }
  }

  // Mirrors Tui::SidekiqStatsComponent::DEFAULT_CONCURRENCY. Used when
  // the cable payload omits concurrency (boot-ordering or partial mock).
  static DEFAULT_CONCURRENCY = 10

  connect() {
    this._boundChanged = this.onSidekiqChanged.bind(this)
    document.addEventListener("tui:sidekiq-changed", this._boundChanged)
  }

  disconnect() {
    if (this._boundChanged) {
      document.removeEventListener("tui:sidekiq-changed", this._boundChanged)
      this._boundChanged = null
    }
  }

  onSidekiqChanged(event) {
    if (!this.hasTuiTransitionOutlet) return
    const detail = event?.detail || {}
    const busy     = this.toInt(detail.busy)
    const enqueued = this.toInt(detail.enqueued)
    const retry    = this.toInt(detail.retry)
    const dead     = this.toInt(detail.dead)
    const concurrency = Math.max(
      this.toInt(detail.concurrency, this.constructor.DEFAULT_CONCURRENCY),
      1
    )

    const prefix = this.prefixValue
    const bs = "b" + this.shortFormat(busy)
    const es = "e" + this.shortFormat(enqueued)
    const rs = "r" + this.shortFormat(retry)
    const ds = "d" + this.shortFormat(dead)
    const value = `${prefix} ${bs} ${es} ${rs} ${ds}`

    const offset = prefix.length + 1 // chars before the first segment starts (typ. 8)
    const bStart = offset
    const bEnd   = bStart + bs.length
    const eStart = bEnd + 1
    const eEnd   = eStart + es.length
    const rStart = eEnd + 1
    const rEnd   = rStart + rs.length
    const dStart = rEnd + 1
    const dEnd   = dStart + ds.length

    const segments = [
      { name: "busy",     range: [bStart, bEnd], color: this.busyColor(busy, enqueued, concurrency) },
      { name: "enqueued", range: [eStart, eEnd], color: this.enqueuedColor(enqueued, concurrency) },
      { name: "retry",    range: [rStart, rEnd], color: this.retryColor(retry) },
      { name: "dead",     range: [dStart, dEnd], color: this.deadColor(dead) }
    ]

    // Push the segments descriptor first so tui-transition's
    // segmentsValueChanged callback owns the post-render class flip; then
    // push the value (which triggers animateDiff). The diff replay also
    // calls applySegments() so the new colors land on the new cells.
    this.tuiTransitionOutlet.element.setAttribute(
      "data-tui-transition-segments-value",
      JSON.stringify(segments)
    )
    this.tuiTransitionOutlet.setValue(value)
  }

  // ─── tier methods (mirror Ruby — keep in sync) ──────────────────────
  busyColor(busy, enqueued, concurrency) {
    if (busy === 0) return "muted"
    const ratio = busy / concurrency
    if (ratio <= 0.8) return "success"
    if (ratio < 1.0)  return "warn"
    return enqueued > 0 ? "danger" : "warn"
  }

  enqueuedColor(enqueued, concurrency) {
    if (enqueued === 0) return "muted"
    const mult = enqueued / concurrency
    if (mult <= 1.0) return "success"
    if (mult <= 2.0) return "warn"
    return "danger"
  }

  retryColor(retry) { return retry > 0 ? "danger" : "muted" }
  deadColor(dead)   { return dead > 0  ? "fatal"  : "muted" }

  // ─── helpers ────────────────────────────────────────────────────────
  toInt(n, fallback = 0) {
    if (n === null || n === undefined) return fallback
    const parsed = parseInt(n, 10)
    return Number.isFinite(parsed) ? parsed : fallback
  }

  shortFormat(n) {
    if (n === null || n === undefined) return ""
    const parsed = parseInt(n, 10)
    if (!Number.isFinite(parsed)) return ""
    const abs = Math.abs(parsed)
    if (abs < 1000)          return abs.toString()
    if (abs < 1_000_000)     return `${Math.floor(abs / 1000)}k`
    if (abs < 1_000_000_000) return `${Math.floor(abs / 1_000_000)}M`
    return `${Math.floor(abs / 1_000_000_000)}B`
  }
}
