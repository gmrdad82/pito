import { Controller } from "@hotwired/stimulus"

/**
 * tui-sync-indicator — Stimulus controller for Tui::SyncIndicatorComponent.
 *
 * Renders one of three visual states on the TST master sync indicator:
 *
 *   synced       → "[ ] sync"  muted, no animation
 *   syncing      → "[x] sync"  accent, shimmer
 *   disconnected → "[ ] sync"  danger (red), color-only, no animation
 *
 * State transitions are driven by document events:
 *
 *   tui:cable-activity    → "syncing" (debounced back to "synced" after SETTLE_MS)
 *                           emitted by tui_status_bar_controller on every cable message
 *   tui:sync-changed      → "disconnected" when detail.state === "disconnected"
 *                           "synced" when detail.state === "synced" (cable reconnect)
 *                           emitted by tui_status_bar_controller on cable lifecycle events
 *
 * Glyph transitions animate with a scramble effect (8 frames × 30 ms = 240 ms)
 * identical in cadence to sessions_scramble_controller.js. Only the inner
 * bracket character scrambles (the `[` and `]` delimiters stay static).
 * Scramble fires only when the NEW glyph differs from the current one.
 *
 * No click handler. No target mode. Single instance: TST only.
 *
 * @see app/components/tui/sync_indicator_component.rb
 * @scramble-source sessions_scramble_controller.js (same chars + frame pattern)
 */

const SCRAMBLE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
const SCRAMBLE_FRAMES = 8
const FRAME_INTERVAL_MS = 30

function randomChar() {
  return SCRAMBLE_CHARS[Math.floor(Math.random() * SCRAMBLE_CHARS.length)]
}

/** Scramble a single character from whatever is currently in `element.textContent`
 *  to `targetGlyph`, then call `onDone` when settled. Returns the interval id
 *  so the caller can cancel mid-flight if a faster transition arrives. */
function scrambleGlyph(element, targetGlyph, onDone) {
  let frame = 0
  const interval = setInterval(() => {
    frame++
    if (frame >= SCRAMBLE_FRAMES) {
      clearInterval(interval)
      element.textContent = `[${targetGlyph}]`
      if (onDone) onDone()
    } else {
      element.textContent = `[${randomChar()}]`
    }
  }, FRAME_INTERVAL_MS)
  return interval
}

export default class extends Controller {
  static values = { state: { type: String, default: "synced" } }
  static SETTLE_MS = 300

  connect() {
    this._onActivity = this.handleActivity.bind(this)
    this._onSyncChanged = this.handleSyncChanged.bind(this)
    document.addEventListener("tui:cable-activity", this._onActivity)
    document.addEventListener("tui:sync-changed", this._onSyncChanged)
    this._settleTimer = null
    this._scrambleInterval = null
    this._currentGlyph = " "
    this.applyState(this.stateValue)
  }

  disconnect() {
    document.removeEventListener("tui:cable-activity", this._onActivity)
    document.removeEventListener("tui:sync-changed", this._onSyncChanged)
    if (this._settleTimer) clearTimeout(this._settleTimer)
    if (this._scrambleInterval) clearInterval(this._scrambleInterval)
  }

  handleActivity() {
    if (this.stateValue === "disconnected") return
    this.applyState("syncing")
    if (this._settleTimer) clearTimeout(this._settleTimer)
    this._settleTimer = setTimeout(() => this.applyState("synced"), this.constructor.SETTLE_MS)
  }

  handleSyncChanged(event) {
    const state = event && event.detail && event.detail.state
    if (!state) return
    if (state === "disconnected") {
      if (this._settleTimer) clearTimeout(this._settleTimer)
      this.applyState("disconnected")
    } else if (state === "synced" && this.stateValue === "disconnected") {
      this.applyState("synced")
    }
  }

  applyState(s) {
    this.stateValue = s
    const box = this.element.querySelector(".tui-sync-indicator__box")
    if (!box) return

    // Only "syncing" gets a non-blank glyph. "disconnected" shares the
    // blank glyph with "synced" — color (danger red) is the differentiator.
    const glyph = s === "syncing" ? "x" : " "

    // Skip scramble if glyph hasn't changed.
    if (glyph === this._currentGlyph) {
      this.element.classList.remove("is-synced", "is-syncing", "is-disconnected")
      this.element.classList.add(`is-${s}`)
      return
    }

    // Cancel any in-flight scramble before starting a new one.
    if (this._scrambleInterval) {
      clearInterval(this._scrambleInterval)
      this._scrambleInterval = null
    }

    const previousGlyph = this._currentGlyph
    this._currentGlyph = glyph

    // Apply class immediately so shimmer/color transitions start right away.
    this.element.classList.remove("is-synced", "is-syncing", "is-disconnected")
    this.element.classList.add(`is-${s}`)

    // Run the scramble on the box.
    this._scrambleInterval = scrambleGlyph(box, glyph, () => {
      this._scrambleInterval = null
    })
  }
}
