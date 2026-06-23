// spec/javascript/cursor_trail_controller.test.js
//
// Vitest suite for pito--cursor-trail (the kitty cursor_trail effect).
//
// The controller POOLS a fixed ring of reused ghost nodes and spawns/decays them
// via a single rAF loop (transform + opacity only). So the tests assert against
// the POOL (a stable set of .pito-cursor-ghost nodes that never grows) and the
// ACTIVE set (.pito-cursor-ghost--on, the ghosts the rAF loop is currently
// fading) — never "a node was created on this keystroke".
//
// COVERAGE
//   - builds a fixed pool of reused nodes on connect (never grows)
//   - activates a pooled ghost on caret movement (after a prior position)
//   - REUSES nodes under rapid input — no allocation per move (perf guard)
//   - no activation on the very first event (no previous position)
//   - no activation when there is no movement (distance ≤ threshold)
//   - NO activation when motion is off (prefers-reduced-motion / data-fx=false)
//   - live-disable: flipping data-fx → "false" snaps active ghosts back to idle
//   - ghosts are pointer-events:none decoration (class + aria-hidden)
//   - disconnect removes the whole pool
//   BIG-JUMP INTERPOLATION (ctrl+arrow / Home / End / far click):
//   - large-distance jump activates MULTIPLE ghosts with positions between prev and next
//   - the head ghost (nearest caret) has a longer decay than the tail ghost
//   - small one-glyph move still activates exactly ONE ghost (hot path unchanged)
//   - motion gate suppresses large-distance jumps as well as small moves
//
// Stimulus connect is async (MutationObserver); we await a macrotask after DOM
// changes. Spawning is rAF-throttled, so we await one animation frame before
// asserting on the active set — same pattern as chatbox_hints_controller.test.js.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import CursorTrailController from "controllers/pito/cursor_trail_controller"

const POOL_SIZE = 10 // mirrors TRAIL_MAX_GHOSTS

function settings(fx) {
  let el = document.getElementById("pito-settings")
  if (!el) { el = document.createElement("div"); el.id = "pito-settings"; document.body.appendChild(el) }
  el.dataset.fx = fx
  return el
}

function mountWrap() {
  const wrap = document.createElement("div")
  wrap.setAttribute("data-controller", "pito--cursor-trail")
  const block = document.createElement("span")
  block.className = "terminal-caret"
  block.style.height = "20px"
  wrap.appendChild(block)
  document.body.appendChild(wrap)
  return wrap
}

function caret(wrap, left, top) {
  wrap.dispatchEvent(new CustomEvent("pito:caret", { bubbles: true, detail: { left, top } }))
}

const pool   = (wrap) => wrap.querySelectorAll(".pito-cursor-ghost")
const active = (wrap) => wrap.querySelectorAll(".pito-cursor-ghost--on")

const tick = () => new Promise((r) => setTimeout(r, 0))
const nextFrame = () => new Promise((r) => requestAnimationFrame(() => r()))

describe("pito--cursor-trail controller", () => {
  let app

  beforeEach(() => {
    // Default: motion enabled (no reduced-motion, fx on).
    window.matchMedia = () => ({ matches: false })
    settings("true")
    app = Application.start()
    app.register("pito--cursor-trail", CursorTrailController)
  })

  afterEach(async () => {
    await app.stop()
    await tick()
    document.body.innerHTML = ""
  })

  it("builds a fixed pool of reused ghost nodes on connect", async () => {
    const wrap = mountWrap()
    await tick()
    expect(pool(wrap).length).toBe(POOL_SIZE)
    expect(active(wrap).length).toBe(0) // idle until the caret moves
  })

  it("activates a pooled ghost when the caret moves (after a prior position)", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)   // establishes the previous position (nothing active yet)
    await nextFrame()
    expect(active(wrap).length).toBe(0)

    caret(wrap, 14, 0)  // a small one-glyph move → one ghost (re)activated next frame
    await nextFrame()
    const on = active(wrap)
    expect(on.length).toBe(1)
    // Ghost is placed at the position the caret LEFT (the previous point).
    expect(on[0].style.transform).toBe("translate(0px, 0px)")
    // It is faded in (opacity set by the rAF loop), not removed.
    expect(parseFloat(on[0].style.opacity)).toBeGreaterThan(0)
  })

  it("reuses pooled nodes under rapid input — no allocation per move", async () => {
    const wrap = mountWrap()
    await tick()

    const before = [...pool(wrap)]
    expect(before.length).toBe(POOL_SIZE)

    // Hammer many moves across several frames (simulated fast typing).
    caret(wrap, 0, 0)
    for (let i = 1; i <= 40; i++) {
      caret(wrap, i * 7, 0)
      await nextFrame()
    }

    const after = [...pool(wrap)]
    // Same count AND the same node objects — the ring was reused, never grown.
    expect(after.length).toBe(POOL_SIZE)
    after.forEach((node, i) => expect(node).toBe(before[i]))
    // Never more concurrently-fading ghosts than the pool holds.
    expect(active(wrap).length).toBeLessThanOrEqual(POOL_SIZE)
  })

  it("does not activate on the very first caret event", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 12, 0)
    await nextFrame()
    expect(active(wrap).length).toBe(0)
  })

  it("does not activate when the caret does not move", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 10, 0)
    caret(wrap, 10, 0) // identical position → distance 0 → no ghost
    await nextFrame()
    expect(active(wrap).length).toBe(0)
  })

  it("copies the caret block height onto an activated ghost (small move = full height)", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 14, 0)  // small move → single full-height ghost (no morph)
    await nextFrame()
    const ghost = active(wrap)[0]
    expect(ghost.style.height).toBe("20px")
    expect(ghost.getAttribute("aria-hidden")).toBe("true")
  })

  it("activates NO ghosts under prefers-reduced-motion", async () => {
    window.matchMedia = () => ({ matches: true })
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 30, 0)
    await nextFrame()
    expect(active(wrap).length).toBe(0)
  })

  it("activates NO ghosts when fx is off (data-fx='false')", async () => {
    settings("false")
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 30, 0)
    await nextFrame()
    expect(active(wrap).length).toBe(0)
  })

  it("live-disables: flipping data-fx to 'false' snaps active ghosts to idle", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 14, 0)    // small move → one ghost
    await nextFrame()
    expect(active(wrap).length).toBe(1)

    settings("false")     // /config fx off broadcast replaces data-fx
    await tick()          // MutationObserver fires
    expect(active(wrap).length).toBe(0)
    expect(pool(wrap).length).toBe(POOL_SIZE) // pool itself is untouched
  })

  it("removes the whole pool on disconnect", async () => {
    const wrap = mountWrap()
    await tick()
    expect(pool(wrap).length).toBe(POOL_SIZE)

    wrap.removeAttribute("data-controller")
    await tick() // Stimulus disconnect
    expect(pool(wrap).length).toBe(0)
  })

  // ── Big-jump comet (ctrl+arrow / Home / End / far click) ───────────────────
  //
  // TRAIL_INTERPOLATE_THRESHOLD_PX = 18 px (≈2 monospace glyphs) so even a short
  // word-jump streaks; a 14px one-glyph move stays on the single-ghost hot path.
  // The comet is 3–5 stretched SEGMENTS (count scales with length) that tile
  // edge-to-edge — no gaps. Caret height is 20px (mountWrap), so morphed segments
  // pinch to ~30% (6px) mid-travel; segment widths tile exactly in headless layout.

  it("(a) activates 3–5 segment ghosts for a large-distance jump, positions between prev and next", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)     // establish prev position
    caret(wrap, 200, 0)   // 200 px — far above TRAIL_INTERPOLATE_THRESHOLD_PX (18)
    await nextFrame()

    const on = active(wrap)
    // The comet is 3–5 segments (count scales with jump length).
    expect(on.length).toBeGreaterThanOrEqual(3)
    expect(on.length).toBeLessThanOrEqual(5)
    // Pool must never grow — all ghosts come from the existing ring.
    expect(pool(wrap).length).toBe(POOL_SIZE)

    // Every activated ghost lies between prev (x=0) and next (x=200) — the caret
    // itself is at 200, so no ghost is placed there — and stays vertically within
    // the caret band [0, 20] (the morph centres the pinched height on the band).
    for (const ghost of on) {
      const match = ghost.style.transform.match(/translate\(([^,]+)px,\s*([^)]+)px\)/)
      const x = parseFloat(match[1])
      const y = parseFloat(match[2])
      const h = parseFloat(ghost.style.height)
      expect(x).toBeGreaterThanOrEqual(0)   // at or past prev
      expect(x).toBeLessThan(200)           // strictly before next (caret is there)
      expect(y).toBeGreaterThanOrEqual(0)           // within the caret band, centred
      expect(y + h).toBeLessThanOrEqual(20 + 0.001) // pinched height fits the band
    }
  })

  it("tiles its segments edge-to-edge — no gaps (continuous comet)", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 200, 0)   // big jump → 3–5 stretched segments
    await nextFrame()

    // Each segment is a stretched block (explicit px width). Sorted by x, every
    // segment's right edge must reach the next segment's left edge — contiguous, never
    // a gap (this is the regression guard against the old dotted "block · gap · block").
    const segs = [ ...active(wrap) ].map((g) => ({
      left:  parseFloat(g.style.transform.match(/translate\(([^,]+)px/)[1]),
      width: parseFloat(g.style.width)
    })).sort((a, b) => a.left - b.left)

    expect(segs.length).toBeGreaterThanOrEqual(3)
    for (let i = 0; i < segs.length - 1; i++) {
      expect(segs[i].left + segs[i].width).toBeGreaterThanOrEqual(segs[i + 1].left - 0.001)
    }
    // The comet spans the whole jump: first segment starts at ~prev, last reaches ~next.
    expect(segs[0].left).toBeLessThanOrEqual(0.001)
    const last = segs[segs.length - 1]
    expect(last.left + last.width).toBeGreaterThanOrEqual(200 - 0.001)
  })

  it("morphs the streak: a mid-travel ghost is shorter than an end ghost (kitty pinch)", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 200, 0)   // big jump → several morphed ghosts
    await nextFrame()

    // Sort active ghosts by x (tail→head along the travel).
    const ghosts = [...active(wrap)].sort((a, b) =>
      parseFloat(a.style.transform.match(/translate\(([^,]+)px/)[1]) -
      parseFloat(b.style.transform.match(/translate\(([^,]+)px/)[1])
    )
    const heightOf = (g) => parseFloat(g.style.height)

    // The start ghost (frac 0) is full height; a ghost nearer the middle of the
    // travel is pinched shorter — that taper is what reads as a comet.
    const startH = heightOf(ghosts[0])
    const midH   = heightOf(ghosts[Math.floor(ghosts.length / 2)])
    expect(startH).toBe(20)            // end of travel = full caret height
    expect(midH).toBeLessThan(startH)  // mid-travel = pinched
  })

  it("head ghost (nearest caret) has longer decay duration than tail ghost", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 200, 0)   // large jump → multiple staggered ghosts
    await nextFrame()

    const ghostNodes = [...wrap.querySelectorAll(".pito-cursor-ghost--on")]
    expect(ghostNodes.length).toBeGreaterThanOrEqual(2)

    // Sort by x position: smallest x = tail (nearest prev), largest x = head (nearest caret).
    ghostNodes.sort((a, b) => {
      const ax = parseFloat(a.style.transform.match(/translate\(([^,]+)px/)[1])
      const bx = parseFloat(b.style.transform.match(/translate\(([^,]+)px/)[1])
      return ax - bx
    })
    const tail = ghostNodes[0]
    const head = ghostNodes[ghostNodes.length - 1]
    // Head lives longer (brighter near caret); tail fades first.
    expect(head._dur).toBeGreaterThan(tail._dur)
  })

  it("(b) small one-glyph move still activates exactly ONE ghost (hot path unchanged)", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 14, 0)    // ~14 px ≈ one monospace glyph — below threshold (18)
    await nextFrame()

    expect(active(wrap).length).toBe(1)
    // Ghost is placed at the position the caret left (prev = 0,0).
    expect(active(wrap)[0].style.transform).toBe("translate(0px, 0px)")
  })

  it("(c) motion gate suppresses ALL ghosts on a large-distance jump", async () => {
    settings("false")
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 200, 0)   // large jump — would produce multiple ghosts if motion were on
    await nextFrame()

    expect(active(wrap).length).toBe(0)
    expect(pool(wrap).length).toBe(POOL_SIZE) // pool itself is untouched
  })
})
