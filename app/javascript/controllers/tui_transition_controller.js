import { Controller } from "@hotwired/stimulus"

/**
 * tui-transition — canonical value-change animator for cable-driven VCs.
 *
 * Exposes two transitions + one decoration via data-attrs:
 *   scramble-settle  — per-character scramble then settle (diff-only).
 *   color-crossfade  — color class swap (fires only on computed-color diff).
 *   shimmer          — continuous gradient sweep (sync VC only).
 *
 * Data-attrs (Stimulus values):
 *   value         (string) — target content; valueValueChanged drives the diff
 *   color         (string) — base color name (muted/accent/busy/enqueued/retry/pink)
 *   activeColor   (string) — when value > 0 (sidekiq kind), this color is used
 *   shimmer       (string) — "yes" / "no"
 *   align         (string) — "left" / "center" / "right" (default left)
 *   duration      (number) — per-cell scramble window in ms (default 200)
 *   stagger       (number) — ms between adjacent cells (default 30)
 *   debounce      (number) — collapse burst writes within this window (default 80)
 *   prefix        (string) — static prefix glued to numeric cells (e.g. "b")
 *   effect        (string) — "scramble-settle" (default) — sole effect today
 *
 * Public API (per-instance):
 *   setValue(v)        / setColor(name)
 *   setActiveColor(n)  / setShimmer(yesNo)
 *   These are thin wrappers that mutate the Stimulus value; the corresponding
 *   *ValueChanged callback owns the animation.
 *
 * Events:
 *   "tui-transition:settled" fires on the host when in-flight scramble drains.
 *   Consumers listen with addEventListener("tui-transition:settled", ..., { once: true }).
 *
 * Reduced motion:
 *   When window.matchMedia("(prefers-reduced-motion: reduce)").matches:
 *     scramble → instant set; color → instant class swap; shimmer → no-op.
 *
 * Kind detection (CSS-class on host):
 *   .tui-sync-word     → sync       (accent default; .is-muted / .is-pink)
 *   .tui-date-time     → datetime   (muted default; .is-notif)
 *   .tui-sidekiq-cell  → sidekiq    (muted default; .is-busy / .is-enqueued / .is-retry)
 *   .sb-section        → breadcrumb (accent default; .is-muted)
 *   .bsb-mode          → mode       (muted default; .is-accent / .is-success / .is-danger)
 *
 * @contract see docs/design.md § Transitions, docs/architecture.md § Pito::Transitions
 */

const SCRAMBLE_ALPHA  = "abcdefghijklmnopqrstuvwxyz"
const SCRAMBLE_DIGITS = "0123456789"

// Map color-name -> CSS class on the host element. We toggle classes so the
// palette stays sourced from the project's stylesheet, not from the controller.
const COLOR_CLASS = {
  sync: {
    accent:   "",            // default class state on .tui-sync-word
    muted:    "is-muted",
    pink:     "is-pink"
  },
  datetime: {
    muted:    "",            // default on .tui-date-time
    accent:   "is-notif"
  },
  sidekiq: {
    muted:    "",            // default on .tui-sidekiq-cell
    busy:     "is-busy",
    enqueued: "is-enqueued",
    retry:    "is-retry"
  },
  breadcrumb: {
    accent:   "",            // default on .sb-section (section accent in CSS)
    muted:    "is-muted"
  },
  mode: {
    muted:    "",            // default on .bsb-mode (muted in CSS)
    accent:   "is-accent",
    success:  "is-success",
    danger:   "is-danger"
  }
}

function prefersReducedMotion() {
  return typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

export default class extends Controller {
  static values = {
    value:       { type: String, default: "" },
    color:       { type: String, default: "muted" },
    activeColor: { type: String, default: "" },
    shimmer:     { type: String, default: "no" },
    align:       { type: String, default: "left" },
    duration:    { type: Number, default: 200 },
    stagger:     { type: Number, default: 30 },
    debounce:    { type: Number, default: 80 },
    prefix:      { type: String, default: "" },
    effect:      { type: String, default: "scramble-settle" }
  }

  connect() {
    // Per-instance state MUST be initialized before any render()/animate call.
    this._debounceTimer = null
    this._animTokens = new Set()

    this.kind = this.detectKind()
    this.applyAlign()
    this.applyColorClass(this.computeColorName())
    this.applyShimmer()
    this.render(this.valueValue)
  }

  disconnect() {
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
      this._debounceTimer = null
    }
    this._animTokens.clear()
  }

  detectKind() {
    if (this.element.classList.contains("tui-sync-word")) return "sync"
    if (this.element.classList.contains("tui-date-time")) return "datetime"
    if (this.element.classList.contains("tui-sidekiq-cell")) return "sidekiq"
    if (this.element.classList.contains("sb-section")) return "breadcrumb"
    if (this.element.classList.contains("bsb-mode")) return "mode"
    return "sync"
  }

  // ─── Stimulus value-changed callbacks ──────────────────────────────
  valueValueChanged(newValue, oldValue) {
    if (typeof oldValue === "undefined") return // initial paint handled in connect
    this.queueAnimate(newValue)
  }

  colorValueChanged(newValue, oldValue) {
    if (typeof oldValue === "undefined") return
    this.applyColorClass(this.computeColorName())
  }

  activeColorValueChanged(newValue, oldValue) {
    if (typeof oldValue === "undefined") return
    this.applyColorClass(this.computeColorName())
  }

  shimmerValueChanged(newValue, oldValue) {
    if (typeof oldValue === "undefined") return
    this.applyShimmer()
  }

  alignValueChanged(newValue, oldValue) {
    if (typeof oldValue === "undefined") return
    this.applyAlign()
  }

  // ─── public API (thin wrappers over Stimulus values) ───────────────
  setValue(v)       { this.valueValue       = String(v) }
  setColor(name)    { this.colorValue       = String(name) }
  setActiveColor(n) { this.activeColorValue = String(n) }
  setShimmer(yesNo) { this.shimmerValue     = yesNo ? "yes" : "no" }

  // ─── color handling ────────────────────────────────────────────────
  computeColorName() {
    if (this.kind === "sidekiq") {
      const numeric = parseInt(this.valueValue, 10)
      if (this.activeColorValue && Number.isFinite(numeric) && numeric > 0) {
        return this.activeColorValue
      }
      return this.colorValue
    }
    return this.colorValue
  }

  applyColorClass(name) {
    const map = COLOR_CLASS[this.kind] || {}
    Object.values(map).forEach((cls) => { if (cls) this.element.classList.remove(cls) })
    const target = map[name]
    if (target) this.element.classList.add(target)
  }

  applyShimmer() {
    if (prefersReducedMotion()) {
      this.element.classList.remove("tui-shimmer")
      return
    }
    if (this.shimmerValue === "yes") this.element.classList.add("tui-shimmer")
    else this.element.classList.remove("tui-shimmer")
  }

  applyAlign() {
    // CSS-only: the host is already inline-block. Setting text-align makes
    // inline-block .tt-char children flow from left/center/right within the
    // min-width slot. For sync VC, "right" anchors the right edge so the
    // next neighbor in TST doesn't get pushed when the word length changes.
    this.element.style.textAlign = this.alignValue
  }

  fireSettled() {
    // Dispatched on the host when all in-flight scramble tweens complete.
    // Consumers can listen with:
    //   el.addEventListener("tui-transition:settled", () => { ... }, { once: true })
    this.element.dispatchEvent(new CustomEvent("tui-transition:settled", {
      detail: { value: this.valueValue }, bubbles: false
    }))
  }

  // ─── animation pipeline ────────────────────────────────────────────
  queueAnimate(newValue) {
    if (prefersReducedMotion()) {
      // Reduced-motion gate: skip the tween, apply instantly.
      this.applyColorClass(this.computeColorName())
      this.render(newValue)
      this.fireSettled()
      return
    }
    if (this._debounceTimer) clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => {
      this._debounceTimer = null
      const from = this._lastRenderedValue ?? ""
      this.applyColorClass(this.computeColorName())
      this.animateDiff(from, newValue)
      this._lastRenderedValue = String(newValue)
    }, this.debounceValue)
  }

  render(value) {
    // abandon in-flight animations
    this._animTokens.clear()
    this.replaceCells(String(value))
    this._lastRenderedValue = String(value)
  }

  replaceCells(str) {
    // Safe DOM construction: clear + append <span> per character.
    while (this.element.firstChild) this.element.removeChild(this.element.firstChild)
    if (this.kind === "sidekiq" && this.prefixValue) {
      const p = document.createElement("span")
      p.className = "cell-prefix"
      p.textContent = this.prefixValue
      this.element.appendChild(p)
    }
    for (let i = 0; i < str.length; i++) {
      const cell = document.createElement("span")
      cell.className = "tt-char"
      cell.dataset.i = String(i)
      cell.textContent = str.charAt(i)
      this.element.appendChild(cell)
    }
  }

  animateDiff(fromRaw, toRaw) {
    const from = String(fromRaw ?? "")
    const to   = String(toRaw ?? "")

    const cells = Array.from(this.element.querySelectorAll(".tt-char"))
    const wantLen = to.length

    if (cells.length !== wantLen) {
      this.handleLengthChange(from, to)
      return
    }

    // Diff-only: collect the indices of positions that changed, then walk them
    // with a sequential stagger counter so the wave is tight regardless of
    // where the diff lands in the string. Unchanged positions stay still.
    let staggerIdx = 0
    for (let i = 0; i < wantLen; i++) {
      const fromCh = from.charAt(i) ?? " "
      const toCh   = to.charAt(i)
      if (fromCh === toCh) continue
      this.scrambleCell(cells[i], toCh, staggerIdx)
      staggerIdx++
    }
    if (staggerIdx === 0) {
      // No diff to animate — fire settled immediately so listeners chained
      // on "no change" don't hang.
      this.fireSettled()
    }
  }

  handleLengthChange(from, to) {
    const fromLen = from.length

    this.replaceCells(to)
    const newCells = Array.from(this.element.querySelectorAll(".tt-char"))

    // Same diff-only behavior with sequential stagger counter across the
    // mixed set of "newly entered" (fade-in) and "changed value" (scramble)
    // cells. Stagger counter ticks once per cell that actually animates.
    let staggerIdx = 0
    newCells.forEach((cell, i) => {
      const wasPresent = i < fromLen
      if (!wasPresent) {
        cell.classList.add("is-entering")
        setTimeout(() => cell.classList.remove("is-entering"), 220)
        staggerIdx++
      } else if (from.charAt(i) !== to.charAt(i)) {
        this.scrambleCell(cell, to.charAt(i), staggerIdx)
        staggerIdx++
      }
    })
    // implicit shrink: rebuilt structure already lacks the removed trailing cells.
    if (staggerIdx === 0) this.fireSettled()
  }

  // scramble-settle: per-character pool selected by character class.
  //   digit position (0-9):  randomize from SCRAMBLE_DIGITS
  //   letter position (a-z): randomize from SCRAMBLE_ALPHA
  //   colon / period / space / dash: pass-through unchanged (no scramble)
  scrambleCell(cell, target, indexFromLeft) {
    // Pass-through for structural characters
    const isPassThrough = /[:. -]/.test(target)
    if (isPassThrough) {
      cell.textContent = target
      return
    }

    const token = Symbol("anim")
    this._animTokens.add(token)
    cell.classList.add("is-scrambling")

    // Per-character class detection for scramble-settle
    const isDigit = /[0-9]/.test(target)
    const isAlpha = /[a-z]/i.test(target)
    const pool = isDigit ? SCRAMBLE_DIGITS
              : isAlpha ? SCRAMBLE_ALPHA
              : target

    const stagger = indexFromLeft * this.staggerValue
    const window  = this.durationValue
    const steps   = 4
    const stepMs  = Math.max(20, Math.floor(window / steps))

    let step = 0
    const tick = () => {
      if (!this._animTokens.has(token)) return
      if (step < steps - 1) {
        const r = pool.charAt(Math.floor(Math.random() * pool.length))
        cell.textContent = r
        step++
        setTimeout(tick, stepMs)
      } else {
        cell.textContent = target
        cell.classList.remove("is-scrambling")
        this._animTokens.delete(token)
        if (this._animTokens.size === 0) this.fireSettled()
      }
    }
    setTimeout(tick, stagger)
  }
}
