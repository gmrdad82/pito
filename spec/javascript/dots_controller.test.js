// spec/javascript/dots_controller.test.js
//
// Tests for pito--dots, pito--done-dispatch, and pito--turn-complete
// Stimulus controllers.
//
// pito--dots: shows on pito:submitted, hides on pito:echo-typed OR
// pito:result-appended (class toggle); pito:done no longer drives it.
// pito--done-dispatch: dispatches its configured event name on connect.
// pito--turn-complete: dispatches "pito:turn-complete" on connect.
//
// Strategy: mount each controller on a minimal DOM scaffold, dispatch
// events, and assert class/event state changes.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import DotsController from "controllers/pito/dots_controller"
import DoneDispatchController from "controllers/pito/done_dispatch_controller"
import TurnCompleteController from "controllers/pito/turn_complete_controller"

// ── Helpers ───────────────────────────────────────────────────────────────────

function tick() {
  return new Promise((r) => setTimeout(r, 0))
}

// ── pito--dots ────────────────────────────────────────────────────────────────

describe("pito--dots controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--dots", DotsController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  function buildDots() {
    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--dots")
    document.body.appendChild(el)
    return el
  }

  it("adds pito-dots--hidden class on connect (starts hidden)", async () => {
    const el = buildDots()
    await tick()
    expect(el.classList.contains("pito-dots--hidden")).toBe(true)
  })

  it("shows dots (removes pito-dots--hidden) on pito:submitted", async () => {
    const el = buildDots()
    await tick()
    expect(el.classList.contains("pito-dots--hidden")).toBe(true)

    document.dispatchEvent(new CustomEvent("pito:submitted"))

    expect(el.classList.contains("pito-dots--hidden")).toBe(false)
  })

  it("hides dots (adds pito-dots--hidden) on pito:echo-typed", async () => {
    const el = buildDots()
    await tick()

    // Show first, then hide when the echo finishes typing.
    document.dispatchEvent(new CustomEvent("pito:submitted"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(false)

    document.dispatchEvent(new CustomEvent("pito:echo-typed"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(true)
  })

  it("hides dots on pito:result-appended (no-echo error fast path)", async () => {
    const el = buildDots()
    await tick()

    // Auth-gated error: no echo, no echo-typed will ever come — the result
    // append must still clear the comet so it does not hang.
    document.dispatchEvent(new CustomEvent("pito:submitted"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(false)

    document.dispatchEvent(new CustomEvent("pito:result-appended"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(true)
  })

  it("does NOT hide dots on pito:done alone (pito:done no longer drives the comet)", async () => {
    const el = buildDots()
    await tick()

    document.dispatchEvent(new CustomEvent("pito:submitted"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(false)

    document.dispatchEvent(new CustomEvent("pito:done"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(false)
  })

  it("show/hide cycle works multiple times", async () => {
    const el = buildDots()
    await tick()

    document.dispatchEvent(new CustomEvent("pito:submitted"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(false)

    document.dispatchEvent(new CustomEvent("pito:echo-typed"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(true)

    document.dispatchEvent(new CustomEvent("pito:submitted"))
    expect(el.classList.contains("pito-dots--hidden")).toBe(false)
  })
})

// ── pito--done-dispatch ───────────────────────────────────────────────────────

describe("pito--done-dispatch controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--done-dispatch", DoneDispatchController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  it("dispatches the configured event name on connect", async () => {
    let caught = null
    document.addEventListener("pito:done", (e) => { caught = e }, { once: true })

    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--done-dispatch")
    el.setAttribute("data-pito--done-dispatch-event-name-value", "pito:done")
    document.body.appendChild(el)

    await tick()

    expect(caught).not.toBeNull()
  })

  it("dispatches the configured custom event name on connect", async () => {
    let caught = null
    document.addEventListener("my:custom-event", (e) => { caught = e }, { once: true })

    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--done-dispatch")
    el.setAttribute("data-pito--done-dispatch-event-name-value", "my:custom-event")
    document.body.appendChild(el)

    await tick()

    expect(caught).not.toBeNull()
  })

  it("dispatched event has bubbles: true", async () => {
    let caught = null
    document.addEventListener("pito:done", (e) => { caught = e }, { once: true })

    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--done-dispatch")
    el.setAttribute("data-pito--done-dispatch-event-name-value", "pito:done")
    document.body.appendChild(el)

    await tick()

    expect(caught?.bubbles).toBe(true)
  })
})

// ── pito--turn-complete ───────────────────────────────────────────────────────

describe("pito--turn-complete controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--turn-complete", TurnCompleteController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  it("dispatches pito:turn-complete on connect", async () => {
    let caught = null
    document.addEventListener("pito:turn-complete", (e) => { caught = e }, { once: true })

    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--turn-complete")
    document.body.appendChild(el)

    await tick()

    expect(caught).not.toBeNull()
  })

  it("pito:turn-complete has bubbles: true", async () => {
    let caught = null
    document.addEventListener("pito:turn-complete", (e) => { caught = e }, { once: true })

    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--turn-complete")
    document.body.appendChild(el)

    await tick()

    expect(caught?.bubbles).toBe(true)
  })

  it("fires once per connect — disconnecting and reconnecting fires again", async () => {
    let count = 0
    document.addEventListener("pito:turn-complete", () => { count++ })

    const el = document.createElement("div")
    el.setAttribute("data-controller", "pito--turn-complete")
    document.body.appendChild(el)
    await tick()

    expect(count).toBe(1)

    // Disconnect by removing from DOM.
    el.remove()
    await tick()

    // Reconnect.
    document.body.appendChild(el)
    await tick()

    expect(count).toBe(2)
  })
})
