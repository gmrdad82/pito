// Pito::CursorTrailController
//
// A kitty-style `cursor_trail` for the terminal block caret. As the caret moves,
// it leaves a short tail of faded ghost blocks at the positions it just left;
// each ghost decays quickly so the block appears to "catch up" with a comet-like
// streak behind it.
//
// It is a SIBLING of pito--terminal-caret on the same wrap and never forks the
// caret machinery — it only listens to the bubbling `pito:caret {left,top}` event
// the caret core emits on every move. Ghosts are absolutely positioned in the
// (position:relative) wrap and are `pointer-events:none`, so they never interfere
// with focus, selection, the sidebar mobile-overlay, or swipe gestures.
//
// PERFORMANCE (typing must stay smooth — this is the hot path on every keystroke):
//   • POOLED nodes — a fixed ring of TRAIL_MAX_GHOSTS reused <div>s, built once
//     on connect and never created/removed per keystroke (no GC / layout churn).
//   • rAF-THROTTLED spawning — caret moves only set a pending position; at most
//     ONE ghost is (re)activated per animation frame (fast bursts coalesce).
//   • COMPOSITOR-FRIENDLY decay — a single rAF loop fades active ghosts touching
//     only `opacity` (+ `transform` for placement, set once on activate); no
//     forced reflow, no per-node animationend listeners, no `animation` restart.
//
// BIG-JUMP COMET (ctrl+arrow / Home / End / far click):
//   A word-jump moves the caret the entire distance in a single `pito:caret` event,
//   so a single-ghost spawn would look like an abrupt pop. When the move distance
//   exceeds TRAIL_INTERPOLATE_THRESHOLD_PX (kept low, ~2 glyphs, so even a short
//   3-letter word-jump shows a streak), #onCaret splits prev → next into 3–5 SEGMENTS
//   (count scales with length) and stores them in pending.ghosts; #frame activates them
//   in that one frame (big jumps are rare). Three things make it a continuous comet:
//     • NO GAPS — each segment ghost is STRETCHED to fill its slice of the jump
//       (width = the segment span), so adjacent segments tile edge-to-edge instead of
//       leaving the dotted "block · gap · block" of fixed 1ch points.
//     • MORPH — each segment's height follows a pinch profile by its start fraction:
//       full height at the start, narrowing to TRAIL_PINCH_MIN_RATIO (~30%) mid-flight,
//       swelling back toward the caret (kept vertically centred) — kitty's stretch.
//     • STAGGER — tail→head decay: the segment nearest the START fades fastest, the
//       one nearest the END (the caret) lingers longest (brightest near the cursor).
//   The small-move path (normal typing) is untouched — one coalesced full-height
//   ghost per frame.
//
// Tunables below mirror the owner's kitty.conf:
//   cursor_trail 10                 -> TRAIL_MAX_GHOSTS
//   cursor_trail_start_threshold 0  -> TRAIL_THRESHOLD_PX (trail on ANY move)
//   cursor_trail_decay 0.01 0.05    -> TRAIL_DECAY_FAST_MS / TRAIL_DECAY_SLOW_MS
//
// Fully gated on motion: prefers-reduced-motion OR `/config fx off` disables the
// trail, live (a `/config fx` broadcast replaces #pito-settings' data-fx).

import { Controller } from "@hotwired/stimulus"
import { motionDisabled } from "pito/settings"

// ── Tunables ──────────────────────────────────────────────────────────────────
const TRAIL_MAX_GHOSTS = 10       // pooled ring size (kitty cursor_trail 10)
const TRAIL_THRESHOLD_PX = 0      // min move distance to spawn (0 = any move)
const TRAIL_DECAY_FAST_MS = 10    // fast fade for big jumps (decay 0.01s)
const TRAIL_DECAY_SLOW_MS = 50    // slow fade for small moves (decay 0.05s)
const TRAIL_START_OPACITY = 1     // solid pito-blue at spawn; the rAF loop fades it to 0
// Distance (px) at/above which a move uses the FAST decay; below it interpolates
// toward SLOW. Roughly one glyph advance feels "slow", a line jump "fast".
const TRAIL_FAST_DISTANCE_PX = 40

// ── Big-jump comet tunables ───────────────────────────────────────────────────
// Moves at/above this distance become a multi-ghost comet instead of the single-
// ghost typing path. Kept LOW (~18 px ≈ 2 monospace glyphs at the 14px base) so
// even a short 3-letter ctrl+arrow word-jump shows a streak — still above a normal
// one-char arrow/typing move (~8 px), which stays on the single-ghost hot path.
const TRAIL_INTERPOLATE_THRESHOLD_PX = 18
// The comet is 3–5 segments depending on jump length: count = clamp(round(dist /
// TRAIL_COMET_SEG_PX), MIN, MAX). Each segment is STRETCHED to fill its slice of the
// jump so adjacent segments tile edge-to-edge (NO gaps) — a continuous streak, not a
// row of separate blocks. SEG_PX ≈ one segment per ~50 px of travel (short word-jump →
// 3, a long line jump → 5).
const TRAIL_COMET_SEG_PX = 50
const TRAIL_COMET_MIN    = 3
const TRAIL_COMET_MAX    = 5
// Pinch profile: a segment's height = full × (this .. 1) by its start fraction of the
// travel — full at the start, narrowing to this ratio at the MIDDLE, swelling back
// toward the caret (kitty's stretch). ~0.3 = the streak squeezes to ~30% height mid-flight.
const TRAIL_PINCH_MIN_RATIO = 0.3
// Big-jump fade window (ms). The single-glyph decay above (10–50 ms) is 1–3 frames —
// fine for typing but invisible for a word-jump comet. A jump's streak fades over a
// PERCEPTIBLE window instead, staggered tail→head so it visibly RETRACTS toward the
// caret (kitty's trail): the tail clears first, the head (by the cursor) lingers.
const TRAIL_COMET_TAIL_MS = 140   // ghost nearest the start — fades first
const TRAIL_COMET_HEAD_MS = 320   // ghost nearest the caret — lingers longest

const now = () =>
  (typeof performance !== "undefined" && performance.now) ? performance.now() : Date.now()

export default class extends Controller {
  connect() {
    this.last = null
    this.head = 0            // ring index of the next ghost to (re)use
    this.pending = null      // most-recent vacated position awaiting a frame
    this.rafId = null
    this.pool = this.#buildPool()

    this.onCaret = this.#onCaret.bind(this)
    this.frame = this.#frame.bind(this)
    this.element.addEventListener("pito:caret", this.onCaret)

    // Re-evaluate the gate live when #pito-settings' data-fx flips.
    const settings = document.getElementById("pito-settings")
    if (settings) {
      this.observer = new MutationObserver(() => {
        if (motionDisabled()) this.#clearGhosts()
      })
      this.observer.observe(settings, { attributes: true, attributeFilter: ["data-fx"] })
    }
  }

  disconnect() {
    this.element.removeEventListener("pito:caret", this.onCaret)
    this.observer?.disconnect()
    if (this.rafId !== null) cancelAnimationFrame(this.rafId)
    this.rafId = null
    this.pending = null
    this.pool.forEach((g) => g.remove())
    this.pool = []
  }

  // ── internals ──────────────────────────────────────────────────────────────

  // Build the reused ghost ring once. Nodes live in the DOM for the controller's
  // lifetime, idle at opacity:0 (the CSS default) until the rAF loop fades them.
  #buildPool() {
    const pool = []
    for (let i = 0; i < TRAIL_MAX_GHOSTS; i++) {
      const ghost = document.createElement("div")
      ghost.className = "pito-cursor-ghost"
      ghost.setAttribute("aria-hidden", "true")
      ghost._active = false
      ghost._born = 0
      ghost._dur = 0
      this.element.appendChild(ghost)
      pool.push(ghost)
    }
    return pool
  }

  #onCaret(event) {
    if (motionDisabled()) { this.last = null; return }

    const next = { left: event.detail.left, top: event.detail.top }
    const prev = this.last
    this.last = next

    // Need a previous position to leave a trail between two points.
    if (!prev) return

    const dist = Math.hypot(next.left - prev.left, next.top - prev.top)
    if (dist <= TRAIL_THRESHOLD_PX) return // no movement → no ghost

    if (dist >= TRAIL_INTERPOLATE_THRESHOLD_PX) {
      // BIG JUMP (ctrl+arrow / Home / End / far click): split prev → next into 3–5
      // SEGMENTS (count scales with length), each stretched to fill its slice so they
      // tile edge-to-edge with NO gaps — a continuous comet, not a dotted line.
      const count = Math.min(
        Math.max(Math.round(dist / TRAIL_COMET_SEG_PX), TRAIL_COMET_MIN),
        TRAIL_COMET_MAX
      )
      const fullH  = this.#caretHeightPx()
      const glyphW = this.#caretWidthPx()
      const dx = next.left - prev.left
      const dy = next.top  - prev.top
      const segW = Math.abs(dx) / count          // horizontal span of one segment
      const ghosts = []
      for (let i = 0; i < count; i++) {
        // Segment i spans fraction [i/count, (i+1)/count] of the jump. Place the ghost
        // at the segment's left edge and stretch its width across the segment (+ one
        // glyph) so segment i and i+1 overlap slightly — never a gap between them.
        const fracA = i / count
        const xA = prev.left + fracA * dx
        const xB = prev.left + ((i + 1) / count) * dx
        const left = Math.min(xA, xB)
        const top  = prev.top + fracA * dy        // horizontal jump → dy 0
        const w    = segW + glyphW
        // MORPH: pinch height by the segment's START fraction — full at the start,
        // narrowing to TRAIL_PINCH_MIN_RATIO at mid-travel (|2·frac − 1| is 1 at 0,
        // 0 at 0.5), swelling back toward the caret. Kept vertically centred on the
        // caret band. (Falls back to full height if the caret height is unknown.)
        const ratio = TRAIL_PINCH_MIN_RATIO + (1 - TRAIL_PINCH_MIN_RATIO) * Math.abs(2 * fracA - 1)
        const h  = fullH ? fullH * ratio : null
        const cy = fullH ? top + (fullH - h) / 2 : top
        // Stagger tail→head over the PERCEPTIBLE comet window: segment 0 (nearest prev
        // / tail) fades fastest; the segment nearest next (head, by the caret) lingers
        // longest — so the streak visibly retracts toward the cursor (kitty).
        const headness = (count === 1) ? 1 : (i / (count - 1))
        const dur = TRAIL_COMET_TAIL_MS + headness * (TRAIL_COMET_HEAD_MS - TRAIL_COMET_TAIL_MS)
        ghosts.push({ at: { left, top: cy }, dur, h, w })
      }
      // Replace any coalesced pending — a new jump supersedes an in-flight one.
      this.pending = { ghosts }
    } else {
      // SMALL MOVE (normal typing hot path): coalesce — only the most-recent
      // vacated position survives to the next frame, so a burst of keystrokes
      // spawns one ghost per frame, not one per event.
      this.pending = { at: prev, dist }
    }

    this.#ensureFrame()
  }

  #ensureFrame() {
    if (this.rafId === null) this.rafId = requestAnimationFrame(this.frame)
  }

  // The single decay loop: apply the pending spawn (one ghost for small moves,
  // several for big jumps), fade every active ghost, and re-arm while work remains.
  // Reads time once per frame.
  #frame() {
    this.rafId = null
    const t = now()

    if (this.pending) {
      if (this.pending.ghosts) {
        // Big jump: activate all comet segments in this frame.
        // Big jumps are rare — paying for several pool activations once is fine.
        for (const { at, dur, h, w } of this.pending.ghosts) {
          this.#activateAt(at, dur, t, h, w)
        }
      } else {
        // Small move: activate the single coalesced ghost (existing hot path).
        this.#activate(this.pending.at, this.pending.dist, t)
      }
      this.pending = null
    }

    let anyActive = false
    for (const ghost of this.pool) {
      if (!ghost._active) continue
      const k = (t - ghost._born) / ghost._dur
      if (k >= 1) {
        ghost._active = false
        ghost.classList.remove("pito-cursor-ghost--on")
        ghost.style.opacity = "0"
      } else {
        // Ease-out fade (1−k)² — softer, more comet-like tail than a linear ramp.
        const e = 1 - k
        ghost.style.opacity = String(TRAIL_START_OPACITY * e * e)
        anyActive = true
      }
    }

    if (anyActive || this.pending) this.#ensureFrame()
  }

  // (Re)activate the next pooled ghost at the vacated position. Larger jumps
  // fade fast (catch-up); small moves linger toward the slow decay.
  // Delegates placement to #activateAt after computing duration from dist.
  #activate(at, dist, t) {
    const factor = Math.min(1, dist / TRAIL_FAST_DISTANCE_PX)
    const dur = TRAIL_DECAY_SLOW_MS - factor * (TRAIL_DECAY_SLOW_MS - TRAIL_DECAY_FAST_MS)
    this.#activateAt(at, dur, t)
  }

  // Low-level ghost activation with an explicit duration (ms). Called by both the
  // single-ghost path (#activate — heightPx/widthPx omitted → full caret-height, 1ch-wide
  // block) and the big-jump comet path (heightPx = pinch height, widthPx = stretched
  // segment width). Advances this.head by 1 per call — mind the ring when activating
  // several at once.
  #activateAt(at, dur, t, heightPx = null, widthPx = null) {
    const ghost = this.pool[this.head]
    this.head = (this.head + 1) % this.pool.length

    if (heightPx != null) {
      ghost.style.height = `${heightPx}px`           // morphed (pinched) height
    } else {
      const h = this.#ghostHeight()
      if (h) ghost.style.height = h                  // full caret height (typing path)
    }
    // Stretched segment width for the comet; reset to "" (→ CSS 1ch) for a small move so
    // a pooled ghost reused after a jump doesn't keep its stretched width.
    ghost.style.width = widthPx != null ? `${widthPx}px` : ""
    ghost.style.transform = `translate(${at.left}px, ${at.top}px)`
    ghost.style.opacity = String(TRAIL_START_OPACITY)
    ghost.classList.add("pito-cursor-ghost--on")
    ghost._born = t
    ghost._dur = dur
    ghost._active = true
  }

  // Match the ghost height to the sibling caret block (CSS provides a fallback).
  #ghostHeight() {
    return this.element.querySelector(".terminal-caret")?.style.height || ""
  }

  // Numeric caret height (px) for the morph maths — parses the inline height the
  // caret core stamps; falls back to the measured box, then 0 (→ no morph).
  #caretHeightPx() {
    const caret = this.element.querySelector(".terminal-caret")
    if (!caret) return 0
    const h = parseFloat(caret.style.height)
    if (!Number.isNaN(h)) return h
    return caret.getBoundingClientRect?.().height || 0
  }

  // Numeric caret width (px ≈ 1 glyph) — used to overlap adjacent comet segments by a
  // glyph so there is never a seam. Measured (the width is CSS `1ch`, not inline); 0 in
  // headless/test layout, where the segment widths already tile exactly.
  #caretWidthPx() {
    const caret = this.element.querySelector(".terminal-caret")
    if (!caret) return 0
    return caret.getBoundingClientRect?.().width || caret.offsetWidth || 0
  }

  // Snap every pooled ghost back to idle (no removal — the ring is reused).
  #clearGhosts() {
    this.pending = null
    if (this.rafId !== null) { cancelAnimationFrame(this.rafId); this.rafId = null }
    for (const ghost of this.pool) {
      ghost._active = false
      ghost.classList.remove("pito-cursor-ghost--on")
      ghost.style.opacity = "0"
    }
  }
}
