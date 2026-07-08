// spec/javascript/pull_refresh_controller.test.js
//
// Vitest (jsdom) suite for pito--pull-refresh (G74): bottom pull-to-refresh,
// Android shell ONLY. A touch starting with the scrollback at the bottom and
// dragging UP past ARM_LIFT reloads on release; short pulls spring back;
// non-shell UAs get no listeners at all.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import PullRefreshController from "controllers/pito/pull_refresh_controller"

// The controller arms once the pull reaches the gauge block's height; under jsdom
// offsetHeight is 0 so it falls back to FALLBACK_LIFT (160) — the effective arm/cap.
const ARM_LIFT = 160

function touchEvent(type, y) {
  const ev = new Event(type, { bubbles: true })
  ev.touches = [ { clientY: y } ]
  return ev
}

// jsdom has no layout: fake the scroll geometry so #atBottom() is controllable.
function fakeGeometry(el, { atBottom }) {
  Object.defineProperty(el, "scrollHeight", { value: 1000, configurable: true })
  Object.defineProperty(el, "clientHeight", { value: 400, configurable: true })
  el.scrollTop = atBottom ? 600 : 100
}

describe("pito--pull-refresh controller", () => {
  let app, el, ctrl, shellSpy

  async function build({ native }) {
    shellSpy = vi.spyOn(PullRefreshController, "enabled").mockReturnValue(native)

    el = document.createElement("div")
    el.setAttribute("data-controller", "pito--pull-refresh")
    document.body.appendChild(el)

    app = Application.start()
    app.register("pito--pull-refresh", PullRefreshController)
    await Promise.resolve()
    ctrl = app.getControllerForElementAndIdentifier(el, "pito--pull-refresh")
  }

  afterEach(async () => {
    vi.restoreAllMocks()
    document.body.innerHTML = ""
    await app.stop()
  })

  it("does nothing outside the Hotwire Native shell (no listeners, no state)", async () => {
    await build({ native: false })
    expect(ctrl.abort).toBeUndefined()

    fakeGeometry(el, { atBottom: true })
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})
    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 300))
    el.dispatchEvent(touchEvent("touchend", 300))
    expect(reload).not.toHaveBeenCalled()
  })

  it("reloads when a bottom-anchored pull passes the threshold", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 500 - (ARM_LIFT + 10)))
    el.dispatchEvent(touchEvent("touchend", 0))

    expect(reload).toHaveBeenCalledTimes(1)
  })

  it("springs back (no reload) when released short of the threshold", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 500 - (ARM_LIFT - 30)))
    el.dispatchEvent(touchEvent("touchend", 0))

    expect(reload).not.toHaveBeenCalled()
    expect(el.style.transform).toBe("")
  })

  it("ignores pulls that start away from the bottom (scrolling history is sacred)", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: false })
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 200))
    el.dispatchEvent(touchEvent("touchend", 0))

    expect(reload).not.toHaveBeenCalled()
  })

  it("fills the gauge by --pull-progress during the drag and arms it at the threshold (G81)", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })

    const template = document.createElement("template")
    template.id = "pito-pull-refresh-hint"
    template.innerHTML = '<div class="pito-pull-hint" data-pull-refresh-hint>shrug pull</div>'
    document.body.appendChild(template)

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 460)) // pull = 40 → progress 40/160 = 0.25
    const hint = el.querySelector("[data-pull-refresh-hint]")
    expect(hint).not.toBeNull()
    // Continuous fill fraction (NOT opacity, NOT per-row) — cascades to the gauge.
    expect(parseFloat(el.style.getPropertyValue("--pull-progress"))).toBeCloseTo(0.25, 2)
    expect(hint.classList.contains("is-armed")).toBe(false)

    el.dispatchEvent(touchEvent("touchmove", 500 - (ARM_LIFT + 10)))
    expect(hint.classList.contains("is-armed")).toBe(true)
    // Fully pulled → fill saturates at 1 (● disc fully blue = release to refresh).
    expect(parseFloat(el.style.getPropertyValue("--pull-progress"))).toBeCloseTo(1, 5)

    // Short release springs back, removes the gauge AND clears the fill so nothing
    // lingers as dead space or a stray blue tint at the bottom of the scrollback.
    el.dispatchEvent(touchEvent("touchmove", 470))
    el.dispatchEvent(touchEvent("touchend", 470))
    expect(el.querySelector("[data-pull-refresh-hint]")).toBeNull()
    expect(el.style.getPropertyValue("--pull-progress")).toBe("")
  })

  it("a DOWNWARD pull is inert — no lift, no fill, no arm, no reload (B1)", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 300))
    el.dispatchEvent(touchEvent("touchmove", 500)) // finger DOWN 200px → delta negative
    expect(el.style.transform).toBe("")
    expect(parseFloat(el.style.getPropertyValue("--pull-progress") || "0")).toBe(0)

    el.dispatchEvent(touchEvent("touchend", 500))
    expect(reload).not.toHaveBeenCalled()
  })

  it("does not spawn a hint (dead space) on a bare touch that never pulls (G-fix)", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })

    const template = document.createElement("template")
    template.id = "pito-pull-refresh-hint"
    template.innerHTML = '<div class="pito-pull-hint" data-pull-refresh-hint>shrug</div>'
    document.body.appendChild(template)

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchend", 500)) // no movement
    expect(el.querySelector("[data-pull-refresh-hint]")).toBeNull()
  })

  it("lifts the pane 1:1 with the finger, capped at the block height", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 440)) // pull = 60 → lift 60 (1:1, no over-run)
    expect(el.style.transform).toBe("translateY(-60px)")

    el.dispatchEvent(touchEvent("touchmove", 60)) // pull = 440 → capped at the block height (160)
    expect(el.style.transform).toBe(`translateY(-${ARM_LIFT}px)`)
  })
})
