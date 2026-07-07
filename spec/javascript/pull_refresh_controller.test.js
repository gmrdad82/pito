// spec/javascript/pull_refresh_controller.test.js
//
// Vitest (jsdom) suite for pito--pull-refresh (G74): bottom pull-to-refresh,
// Android shell ONLY. A touch starting with the scrollback at the bottom and
// dragging UP past THRESHOLD_PX reloads on release; short pulls spring back;
// non-shell UAs get no listeners at all.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import PullRefreshController from "controllers/pito/pull_refresh_controller"

const THRESHOLD_PX = 150

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
    el.dispatchEvent(touchEvent("touchmove", 500 - (THRESHOLD_PX + 10)))
    el.dispatchEvent(touchEvent("touchend", 0))

    expect(reload).toHaveBeenCalledTimes(1)
  })

  it("springs back (no reload) when released short of the threshold", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 500 - (THRESHOLD_PX - 30)))
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

  it("reveals the shrug hint during the drag and arms it at the threshold (G81)", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })

    const template = document.createElement("template")
    template.id = "pito-pull-refresh-hint"
    template.innerHTML = '<div class="pito-pull-hint" data-pull-refresh-hint>shrug pull</div>'
    document.body.appendChild(template)

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 425)) // pull = 75 = half threshold
    const hint = el.querySelector("[data-pull-refresh-hint]")
    expect(hint).not.toBeNull()
    expect(parseFloat(hint.style.opacity)).toBeCloseTo(0.5)
    expect(hint.classList.contains("is-armed")).toBe(false)

    el.dispatchEvent(touchEvent("touchmove", 500 - (THRESHOLD_PX + 10)))
    expect(hint.classList.contains("is-armed")).toBe(true)

    // Short release resets it
    el.dispatchEvent(touchEvent("touchmove", 460))
    el.dispatchEvent(touchEvent("touchend", 460))
    expect(hint.classList.contains("is-armed")).toBe(false)
    expect(String(hint.style.opacity)).toBe("0")
  })

  it("lifts the pane during the drag as feedback (capped)", async () => {
    await build({ native: true })
    fakeGeometry(el, { atBottom: true })

    el.dispatchEvent(touchEvent("touchstart", 500))
    el.dispatchEvent(touchEvent("touchmove", 440)) // pull = 60 → lift 60px
    expect(el.style.transform).toBe("translateY(-60px)")

    el.dispatchEvent(touchEvent("touchmove", 200)) // pull = 300 → capped at 150px
    expect(el.style.transform).toBe("translateY(-150px)")
  })
})
