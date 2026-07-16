// spec/javascript/scrollback_controller.test.js
//
// Tests for pito--scrollback Stimulus controller (scrollback_controller.js).
//
// Strategy: mount the real controller on a jsdom div, then trigger events and
// DOM mutations and assert scrollTo behaviour via a counter function.
//
// jsdom layout limitations:
//   - scrollHeight, scrollTop, clientHeight are always 0 — must be overridden
//     via Object.defineProperty for each test that cares about scroll position.
//   - scrollTo does not exist on jsdom elements — stubbed on the prototype.
//   - Stimulus needs a real ~10ms delay to connect in jsdom (not just setTimeout 0).
//     MutationObserver callbacks in jsdom are also asynchronous and require a real
//     wait — tests use `waitForConnect()` (10ms) and `waitForMO()` (50ms).
//   - requestAnimationFrame in jsdom does NOT run synchronously after connect —
//     it fires asynchronously, after the 10ms connect wait. waitForConnect()
//     explicitly flushes the connect-time rAF re-scroll (by awaiting a fresh
//     rAF, which is FIFO and so runs after it) so scroll counts are
//     deterministic before any test snapshots them.
//   - Smooth-scroll animation timing (SMOOTH_SCROLL_GRACE 600 ms flag) cannot
//     be simulated in jsdom. The programmaticScrolling flag is set to false after
//     the connect-time grace timer (setTimeout 0) fires.
//
// Behaviours verified (THE PURGE, owner 2026-07-13 — the scrollback never
// scrolls on its own; ctrl+home/end pills are the navigation):
//   1. connect jumps instantly to the end (page load / conversation resume)
//   2. Appended children NEVER trigger a scroll (the purged follow feature)
//   3. Appended echo/non-echo nodes still dispatch their bus events
//   4. pito:submitted jumps to the end (the user just acted)
//   5. connect SKIPS the jump-to-end when the URL has an #event_<id> anchor
//      (resume-to-a-specific-event) — pito--anchor-jump owns the scroll then

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ScrollbackController from "controllers/pito/scrollback_controller"

// ── jsdom stubs ───────────────────────────────────────────────────────────────
// jsdom does not implement scrollTo on elements.
if (!Element.prototype.scrollTo) {
  Element.prototype.scrollTo = function () {}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Build and connect a scrollback element. Returns { el, scrollCalls }.
// scrollCalls is an array that captures each scrollTo call's argument.
function buildScrollback(layoutOpts = {}) {
  const el = document.createElement("div")
  el.id = "pito-scrollback"
  el.setAttribute("data-controller", "pito--scrollback")
  document.body.appendChild(el)

  const { scrollHeight = 500, clientHeight = 300, scrollTop = 0 } = layoutOpts
  let _scrollTop = scrollTop
  Object.defineProperty(el, "scrollHeight", { get: () => scrollHeight, configurable: true })
  Object.defineProperty(el, "clientHeight", { get: () => clientHeight, configurable: true })
  Object.defineProperty(el, "scrollTop", {
    get: () => _scrollTop,
    set: (v) => { _scrollTop = v },
    configurable: true,
  })

  const scrollCalls = []
  el.scrollTo = (opts) => scrollCalls.push(opts)

  return { el, scrollCalls }
}

// Wait for Stimulus to connect (10ms is enough in jsdom), then flush the
// connect-time requestAnimationFrame re-scroll: rAF callbacks are FIFO in
// jsdom, so awaiting a fresh rAF here guarantees the controller's earlier
// connect rAF has already run.
function waitForConnect() {
  return new Promise((r) => setTimeout(r, 10))
    .then(() => new Promise((r) => requestAnimationFrame(() => r())))
}

// Wait for MutationObserver callbacks to flush (jsdom dispatches them asynchronously).
function waitForMO() {
  return new Promise((r) => setTimeout(r, 50))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--scrollback controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--scrollback", ScrollbackController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
    window.location.hash = ""
  })

  it("jumps instantly to the end on connect (reload / resume, no anchor)", async () => {
    window.location.hash = ""
    const { scrollCalls } = buildScrollback()
    await waitForConnect()

    expect(scrollCalls.length).toBeGreaterThan(0)
    expect(scrollCalls[0]).toMatchObject({ top: 500, behavior: "instant" })
  })

  it("does NOT jump to the end on connect when the URL has an #event_<id> anchor", async () => {
    window.location.hash = "#event_123"
    const { scrollCalls } = buildScrollback()
    await waitForConnect()

    expect(scrollCalls.length).toBe(0)
  })

  it("NEVER scrolls when children are appended (the purged follow feature)", async () => {
    const { el, scrollCalls } = buildScrollback()
    await waitForConnect()
    const before = scrollCalls.length

    const node = document.createElement("div")
    node.innerHTML = "<span>new message</span>"
    el.appendChild(node)
    await waitForMO()

    expect(scrollCalls.length).toBe(before)
  })

  it("still announces appended segments on the event bus", async () => {
    const { el } = buildScrollback()
    await waitForConnect()

    const seen = []
    const record = (e) => seen.push(e.type)
    document.addEventListener("pito:echo-appended", record)
    document.addEventListener("pito:result-appended", record)

    const echo = document.createElement("div")
    echo.innerHTML = "<div data-accent=\"purple\"></div>"
    el.appendChild(echo)
    const result = document.createElement("div")
    result.innerHTML = "<span>answer</span>"
    el.appendChild(result)
    await waitForMO()

    expect(seen).toContain("pito:echo-appended")
    expect(seen).toContain("pito:result-appended")
    document.removeEventListener("pito:echo-appended", record)
    document.removeEventListener("pito:result-appended", record)
  })

  it("pito:submitted jumps to the end (the user just acted)", async () => {
    const { scrollCalls } = buildScrollback()
    await waitForConnect()
    const before = scrollCalls.length

    document.dispatchEvent(new CustomEvent("pito:submitted"))

    expect(scrollCalls.length).toBeGreaterThan(before)
    expect(scrollCalls.at(-1)).toMatchObject({ top: 500 })
  })
})
