// Pito::DiffRevealController  (pito--diff-reveal)
//
// Animates a set of `cell` targets through a two-phase diff reveal:
//
//   Phase 1 (subtractions) — for every cell, reverse-delete its `removed`
//                             middle (CHARS_TICK units per TICK_MS tick) until
//                             the cell shows only prefix + suffix.
//   Phase 2 (additions)    — for every cell, type its `added` middle in
//                             forward order until the cell shows its final `to`.
//
// This is general and theme-agnostic.  Whether "preview" animates only the
// added marker or "apply" animates the entire list-to-quip replacement is
// purely a consequence of what `data-from` / textContent the server emits —
// the controller never inspects `phaseValue`.
//
// Data-attribute contract (emitted by ThemeDiffComponent):
//
//   Wrapper element:
//     data-controller="pito--diff-reveal"
//     data-pito--diff-reveal-granularity-value="char"  (or "line")
//     data-pito--diff-reveal-phase-value="preview"     (or "apply")
//
//   Each animatable cell:
//     data-pito--diff-reveal-target="cell"
//     data-from="<pre-transform text>"   ← textContent before the diff
//     (textContent = final/post-transform text — reload-correct)
//
// Skip conditions (show final instantly, no animation):
//   • prefers-reduced-motion matches
//   • window.__pitoReady is falsy  (initial page load, not a live cable event)
//   • fxEnabled() returns false    (user has FX disabled in settings)
//   • opts.instant from reveal_queue backpressure
//
// Queue discipline (mirrors typewriter_controller):
//   A single enqueue() call covers all cells.  On instant/cancel/disconnect,
//   every cell is set to its final `to` and the resolve is called so the FIFO
//   never hangs.

import { Controller } from "@hotwired/stimulus"
import { enqueue }    from "pito/reveal_queue"
import { fxEnabled }  from "pito/settings"
import { TICK_MS, CHARS_TICK } from "pito/typing"
import { diffParts, renderCell, splitUnits } from "pito/diff"

export default class extends Controller {
  static targets = ["cell"]
  static values  = { granularity: String, phase: String }

  connect() {
    if (this.#skipAnimation()) return
    if (!this.hasCellTarget) return

    // Guard double-connect (Turbo may reconnect the same element).
    if (this._connected) return
    this._connected = true
    this._cancelled = false

    const gran = this.granularityValue || "char"

    // Build per-cell diff data.  The element's textContent is the final (new)
    // text; data-from holds the pre-transform text.
    const cells = this.cellTargets.map(el => {
      const from = el.dataset.from ?? ""
      const to   = el.textContent
      const parts = diffParts(from, to, gran)
      const removedUnits = splitUnits(parts.removed, gran)
      const addedUnits   = splitUnits(parts.added,   gran)
      return { el, to, prefix: parts.prefix, suffix: parts.suffix, removedUnits, addedUnits }
    })

    // Blank every cell to its `from` state while the job waits in the queue.
    for (const c of cells) {
      c.el.textContent = renderCell(c.prefix, c.removedUnits.join(""), c.suffix)
    }

    // Stable cancelled reference for the closure.
    const cancelled = () => this._cancelled

    enqueue(({ instant } = {}) => {
      return new Promise(resolve => {
        // Store resolver so disconnect() can settle the in-flight job.
        this._resolve = () => { this._resolve = null; resolve() }

        // Show final state immediately on skip conditions.
        if (instant || cancelled()) {
          for (const c of cells) c.el.textContent = c.to
          this._resolve()
          return
        }

        // ── Phase 1: reverse-delete `removed` from every cell ──────────────
        //
        // We advance CHARS_TICK units per tick across ALL cells simultaneously
        // (one shared budget per tick, wrapping across cells in order).

        // Mutable state for phase 1: how many units remain in each cell.
        const p1Remaining = cells.map(c => c.removedUnits.length)

        const runPhase1 = () => {
          if (cancelled()) {
            for (const c of cells) c.el.textContent = c.to
            this._resolve?.()
            return
          }

          let budget = CHARS_TICK
          let anyLeft = false

          for (let i = 0; i < cells.length; i++) {
            if (p1Remaining[i] <= 0) continue
            anyLeft = true
            const drop = Math.min(budget, p1Remaining[i])
            p1Remaining[i] -= drop
            budget -= drop

            // Render: prefix + remaining-removed-tail + suffix
            const mid = cells[i].removedUnits.slice(0, p1Remaining[i]).join("")
            cells[i].el.textContent = renderCell(cells[i].prefix, mid, cells[i].suffix)

            if (budget <= 0) break
          }

          if (!anyLeft) {
            // Phase 1 complete — ensure clean prefix+suffix on all cells.
            for (const c of cells) {
              c.el.textContent = renderCell(c.prefix, "", c.suffix)
            }
            this._timer = setTimeout(runPhase2Start, TICK_MS)
          } else {
            this._timer = setTimeout(runPhase1, TICK_MS)
          }
        }

        // ── Phase 2: type `added` into every cell ──────────────────────────
        //
        // Same budget model as phase 1, but growing forward.

        const p2Progress = cells.map(() => 0)

        const runPhase2Start = () => {
          if (cancelled()) {
            for (const c of cells) c.el.textContent = c.to
            this._resolve?.()
            return
          }
          runPhase2Tick()
        }

        const runPhase2Tick = () => {
          if (cancelled()) {
            for (const c of cells) c.el.textContent = c.to
            this._resolve?.()
            return
          }

          let budget = CHARS_TICK
          let anyLeft = false

          for (let i = 0; i < cells.length; i++) {
            const total = cells[i].addedUnits.length
            if (p2Progress[i] >= total) continue
            anyLeft = true
            const advance = Math.min(budget, total - p2Progress[i])
            p2Progress[i] += advance
            budget -= advance

            const mid = cells[i].addedUnits.slice(0, p2Progress[i]).join("")
            cells[i].el.textContent = renderCell(cells[i].prefix, mid, cells[i].suffix)

            if (budget <= 0) break
          }

          if (!anyLeft) {
            // Phase 2 complete — ensure exact final text on all cells.
            for (const c of cells) c.el.textContent = c.to
            this._resolve?.()
          } else {
            this._timer = setTimeout(runPhase2Tick, TICK_MS)
          }
        }

        // Kick off phase 1.  If every cell has no removals, go straight to
        // phase 2 (setTimeout gives the browser a paint frame either way).
        const hasAnyRemovals = cells.some(c => c.removedUnits.length > 0)
        if (hasAnyRemovals) {
          this._timer = setTimeout(runPhase1, TICK_MS)
        } else {
          this._timer = setTimeout(runPhase2Start, TICK_MS)
        }
      })
    })
  }

  disconnect() {
    this._cancelled = true
    clearTimeout(this._timer)

    // Settle any in-flight reveal promise so the shared queue isn't left hanging.
    this._resolve?.()
  }

  // ── private ─────────────────────────────────────────────────────────────────

  #skipAnimation() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return true
    if (!window.__pitoReady) return true
    if (!fxEnabled()) return true
    return false
  }
}
