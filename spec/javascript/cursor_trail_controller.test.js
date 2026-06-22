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

    caret(wrap, 30, 0)  // a real move → one ghost (re)activated next frame
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

  it("copies the caret block height onto an activated ghost", async () => {
    const wrap = mountWrap()
    await tick()

    caret(wrap, 0, 0)
    caret(wrap, 30, 0)
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
    caret(wrap, 30, 0)
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
})
