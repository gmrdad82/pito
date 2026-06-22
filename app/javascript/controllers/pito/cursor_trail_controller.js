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
const TRAIL_START_OPACITY = 0.6   // opacity a freshly-spawned ghost fades down from
// Distance (px) at/above which a move uses the FAST decay; below it interpolates
// toward SLOW. Roughly one glyph advance feels "slow", a line jump "fast".
const TRAIL_FAST_DISTANCE_PX = 40

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

    // Coalesce: only the most-recent vacated position survives to the next frame,
    // so a burst of keystrokes spawns one ghost per frame, not one per event.
    this.pending = { at: prev, dist }
    this.#ensureFrame()
  }

  #ensureFrame() {
    if (this.rafId === null) this.rafId = requestAnimationFrame(this.frame)
  }

  // The single decay loop: apply at most one pending spawn, fade every active
  // ghost via opacity, and re-arm while work remains. Reads time once per frame.
  #frame() {
    this.rafId = null
    const t = now()

    if (this.pending) {
      this.#activate(this.pending.at, this.pending.dist, t)
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
        ghost.style.opacity = String(TRAIL_START_OPACITY * (1 - k))
        anyActive = true
      }
    }

    if (anyActive || this.pending) this.#ensureFrame()
  }

  // (Re)activate the next pooled ghost at the vacated position. Larger jumps
  // fade fast (catch-up); small moves linger toward the slow decay.
  #activate(at, dist, t) {
    const ghost = this.pool[this.head]
    this.head = (this.head + 1) % this.pool.length

    const factor = Math.min(1, dist / TRAIL_FAST_DISTANCE_PX)
    const dur = TRAIL_DECAY_SLOW_MS - factor * (TRAIL_DECAY_SLOW_MS - TRAIL_DECAY_FAST_MS)

    const h = this.#ghostHeight()
    if (h) ghost.style.height = h
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
