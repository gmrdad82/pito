// spec/javascript/bar_reveal_controller.test.js
//
// pito--bar-reveal — the score-bar / TTB `=` fill's own reveal (fx-independent).
// Motion off → leaves the fill whole. Motion on → arms `.is-revealing`, then adds
// `.on` after a lead-in + a per-bucket stagger (from the fill's pito-shimmer-dN).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"

const mockState = { motion: false }
vi.mock("pito/settings", () => ({ motionDisabled: () => mockState.motion }))

import BarRevealController from "controllers/pito/bar_reveal_controller"

const tick = (ms = 0) => new Promise((r) => setTimeout(r, ms))

function build(klass = "") {
  const el = document.createElement("span")
  el.className = `pito-ttb__fill pito-bar-reveal ${klass}`.trim()
  el.setAttribute("data-controller", "pito--bar-reveal")
  el.textContent = "===="
  document.body.appendChild(el)
  return el
}

describe("BarRevealController", () => {
  let app

  beforeEach(() => {
    mockState.motion = false
    vi.stubGlobal("requestAnimationFrame", (cb) => { cb(); return 1 })
    app = Application.start()
    app.register("pito--bar-reveal", BarRevealController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })

  it("arms is-revealing then adds .on after the lead-in (motion on)", async () => {
    const el = build("pito-shimmer-d0")
    await tick() // connect
    expect(el.classList.contains("is-revealing")).toBe(true)
    expect(el.classList.contains("on")).toBe(false)
    await tick(150) // > LEAD_IN (80) + d0 stagger (0)
    expect(el.classList.contains("on")).toBe(true)
  })

  it("staggers the .on start by the pito-shimmer-dN bucket", async () => {
    const el = build("pito-shimmer-d10") // 80 + 10*35 = 430ms
    await tick()
    await tick(150)
    expect(el.classList.contains("on")).toBe(false) // not yet (well before 430ms)
    await tick(400)
    expect(el.classList.contains("on")).toBe(true)
  })

  it("does nothing when motion is disabled (fill stays whole)", async () => {
    mockState.motion = true
    const el = build("pito-shimmer-d0")
    await tick()
    expect(el.classList.contains("is-revealing")).toBe(false)
    expect(el.classList.contains("on")).toBe(false)
  })

  it("clears the pending timer on disconnect (no reveal after teardown)", async () => {
    const el = build("pito-shimmer-d5")
    await tick()
    el.remove()
    await tick(400)
    expect(el.classList.contains("on")).toBe(false)
  })
})
