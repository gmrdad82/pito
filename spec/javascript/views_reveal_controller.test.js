// spec/javascript/views_reveal_controller.test.js
//
// The Views metric reveal (variant "D", extends the base metric-reveal engine).
// Fail-open: when motion is disabled (fx off / reduced-motion) it leaves the
// chart whole; otherwise it arms `.is-revealing` and, after a lead-in, wipes the
// braille rows in BOTTOM→UP by adding `.on` to each row span in turn (the wipe +
// trailing glow ride CSS transitions on `.on`).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"

const mockState = { motion: false }
vi.mock("pito/settings", () => ({ motionDisabled: () => mockState.motion }))

import ViewsRevealController from "controllers/pito/views_reveal_controller"

const tick = (ms = 0) => new Promise((r) => setTimeout(r, ms))
const ROWS = 11

function buildDOM() {
  const el = document.createElement("div")
  el.className = "pito-metric pito-metric--views"
  el.setAttribute("data-controller", "pito--views-reveal")
  const plot = document.createElement("div")
  plot.setAttribute("data-pito--views-reveal-target", "plot")
  el.appendChild(plot)
  for (let i = 0; i < ROWS; i++) {
    const row = document.createElement("span")
    row.className = "pito-metric__row"
    row.setAttribute("data-pito--views-reveal-target", "row")
    plot.appendChild(row)
  }
  document.body.appendChild(el)
  return el
}

const onRows = (el) => [...el.querySelectorAll(".pito-metric__row")].filter((r) => r.classList.contains("on"))

describe("ViewsRevealController", () => {
  let app

  beforeEach(() => {
    mockState.motion = false
    vi.stubGlobal("requestAnimationFrame", (cb) => { cb(); return 1 })
    app = Application.start()
    app.register("pito--views-reveal", ViewsRevealController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })

  it("arms the reveal, then wipes rows in bottom→up after the lead-in", async () => {
    const el = buildDOM()
    await tick() // let Stimulus connect

    expect(el.classList.contains("is-revealing")).toBe(true)
    expect(onRows(el).length).toBe(0) // lead-in: nothing revealed yet

    await tick(320) // > LEAD_IN (300) → first (bottom) row on
    const rows = [...el.querySelectorAll(".pito-metric__row")]
    expect(rows[rows.length - 1].classList.contains("on")).toBe(true) // bottom first
    expect(rows[0].classList.contains("on")).toBe(false)              // top still waiting

    await tick(ROWS * 130 + 100) // all cadence steps elapse
    expect(onRows(el).length).toBe(ROWS) // every row revealed
  })

  it("does nothing when motion is disabled (chart stays whole)", async () => {
    mockState.motion = true
    const el = buildDOM()
    await tick()

    expect(el.classList.contains("is-revealing")).toBe(false)
    expect(onRows(el).length).toBe(0)
  })

  it("clears pending row timers on disconnect (no reveal after teardown)", async () => {
    const el = buildDOM()
    await tick() // connect (lead-in pending)
    el.remove() // disconnect before the lead-in fires

    await tick(320 + ROWS * 130)
    // element detached; nothing should have flipped to `.on`
    expect(onRows(el).length).toBe(0)
  })
})
