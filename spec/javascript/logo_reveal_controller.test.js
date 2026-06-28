// spec/javascript/logo_reveal_controller.test.js
//
// pito--logo-reveal — the PITO logo's broken-neon reveal. Motion off → solid
// logo (no is-revealing). Motion on → arms `.is-revealing` and lights every cell
// (each at a random time). Timers are cleared on disconnect.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"

const mockState = { motion: false }
vi.mock("pito/settings", () => ({ motionDisabled: () => mockState.motion }))

import LogoRevealController from "controllers/pito/logo_reveal_controller"

const tick = (ms = 0) => new Promise((r) => setTimeout(r, ms))

function build() {
  const pre = document.createElement("pre")
  pre.className = "pito-logo"
  pre.setAttribute("data-controller", "pito--logo-reveal")
  // 12 glyph cells across 2 rows
  for (let r = 0; r < 2; r++) {
    const row = document.createElement("span")
    for (let i = 0; i < 6; i++) {
      const cell = document.createElement("span")
      cell.className = "pito-logo__cell"
      cell.textContent = "█"
      row.appendChild(cell)
    }
    pre.appendChild(row)
  }
  document.body.appendChild(pre)
  return pre
}

const lit = (el) => [...el.querySelectorAll(".pito-logo__cell.lit")].length

describe("LogoRevealController", () => {
  let app

  beforeEach(() => {
    mockState.motion = false
    app = Application.start()
    app.register("pito--logo-reveal", LogoRevealController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
  })

  it("arms is-revealing and lights every cell within the reveal window (motion on)", async () => {
    const pre = build()
    await tick()
    expect(pre.classList.contains("is-revealing")).toBe(true)
    await tick(1000) // > REVEAL_WINDOW_MS (900)
    expect(lit(pre)).toBe(12) // all cells lit
  })

  it("does nothing when motion is disabled (logo stays solid)", async () => {
    mockState.motion = true
    const pre = build()
    await tick()
    expect(pre.classList.contains("is-revealing")).toBe(false)
    expect(lit(pre)).toBe(0)
  })

  it("clears timers on disconnect (no cells light after teardown)", async () => {
    const pre = build()
    await tick()
    pre.remove()
    await tick(1000)
    expect(lit(pre)).toBe(0)
  })
})
