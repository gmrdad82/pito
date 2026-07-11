// spec/javascript/pull_refresh_controller.test.js
//
// Vitest (jsdom) suite for pito--pull-refresh: Brave-style bottom pull-to-refresh.
// A touch starting with the scrollback at the bottom and dragging UP floats the
// fixed spinner tile in from the bottom edge (cloned from the layout <template>
// onto <body>), tracks the finger 1:1, rotates the arrow with the drag, and
// FIRES the reload the moment the pull crosses 30% of the viewport height — no
// release needed. Short pulls park the tile back out; non-touch UAs get no
// listeners at all. The scrollback content itself never moves.

import { describe, it, expect, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import PullRefreshController from "controllers/pito/pull_refresh_controller"

// jsdom's default viewport is 768px tall → the fire threshold is 230.4px.
const THRESHOLD = () => window.innerHeight * 0.3

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

function appendSpinnerTemplate() {
  const template = document.createElement("template")
  template.id = "pito-pull-refresh-spinner"
  template.innerHTML =
    '<div class="pito-pull-spinner" data-pull-refresh-spinner><svg></svg></div>'
  document.body.appendChild(template)
}

const spinner = () => document.querySelector("[data-pull-refresh-spinner]")

describe("pito--pull-refresh controller", () => {
  let app, el, ctrl

  async function build({ enabled }) {
    vi.spyOn(PullRefreshController, "enabled").mockReturnValue(enabled)

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
    vi.useRealTimers()
    document.body.innerHTML = ""
    await app.stop()
  })

  it("does nothing when the gate is off (no listeners, no state)", async () => {
    await build({ enabled: false })
    expect(ctrl.abort).toBeUndefined()

    fakeGeometry(el, { atBottom: true })
    appendSpinnerTemplate()
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})
    el.dispatchEvent(touchEvent("touchstart", 700))
    el.dispatchEvent(touchEvent("touchmove", 300))
    el.dispatchEvent(touchEvent("touchend", 300))
    expect(reload).not.toHaveBeenCalled()
    expect(spinner()).toBeNull()
  })

  it("floats the spinner in and tracks the drag 1:1, arrow rotating with the pull", async () => {
    await build({ enabled: true })
    fakeGeometry(el, { atBottom: true })
    appendSpinnerTemplate()

    el.dispatchEvent(touchEvent("touchstart", 700))
    el.dispatchEvent(touchEvent("touchmove", 660)) // pull = 40px

    const tile = spinner()
    expect(tile).not.toBeNull()
    expect(tile.style.transform).toBe("translate(-50%, calc(100% - 40px))")
    // 40px × 1.6°/px = 64° — the arrow winds up with the drag.
    expect(tile.querySelector("svg").style.transform).toBe("rotate(64.0deg)")
    // The scrollback content never moves (the old approach lifted the pane).
    expect(el.style.transform).toBe("")
  })

  it("fires the reload the moment the pull crosses 30% of the viewport — before release", async () => {
    await build({ enabled: true })
    fakeGeometry(el, { atBottom: true })
    appendSpinnerTemplate()
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 700))
    el.dispatchEvent(touchEvent("touchmove", 700 - (THRESHOLD() + 10)))

    expect(reload).toHaveBeenCalledTimes(1) // fired mid-drag, no touchend yet
    expect(spinner().classList.contains("is-firing")).toBe(true)

    // Release afterwards neither re-fires nor parks the firing tile away.
    el.dispatchEvent(touchEvent("touchend", 0))
    expect(reload).toHaveBeenCalledTimes(1)
    expect(spinner()).not.toBeNull()
  })

  it("parks the spinner back out (no reload) when released short of the threshold", async () => {
    vi.useFakeTimers()
    await build({ enabled: true })
    fakeGeometry(el, { atBottom: true })
    appendSpinnerTemplate()
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 700))
    el.dispatchEvent(touchEvent("touchmove", 600)) // pull = 100px < threshold
    el.dispatchEvent(touchEvent("touchend", 600))

    expect(reload).not.toHaveBeenCalled()
    expect(spinner().style.transform).toBe("translate(-50%, 100%)") // sliding out

    vi.advanceTimersByTime(300) // removal fallback timer
    expect(spinner()).toBeNull()
  })

  it("ignores pulls that start away from the bottom (scrolling history is sacred)", async () => {
    await build({ enabled: true })
    fakeGeometry(el, { atBottom: false })
    appendSpinnerTemplate()
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 700))
    el.dispatchEvent(touchEvent("touchmove", 200))
    el.dispatchEvent(touchEvent("touchend", 0))

    expect(reload).not.toHaveBeenCalled()
    expect(spinner()).toBeNull()
  })

  it("a DOWNWARD pull is inert — no spinner, no reload", async () => {
    await build({ enabled: true })
    fakeGeometry(el, { atBottom: true })
    appendSpinnerTemplate()
    const reload = vi.spyOn(ctrl, "_reload").mockImplementation(() => {})

    el.dispatchEvent(touchEvent("touchstart", 300))
    el.dispatchEvent(touchEvent("touchmove", 500)) // finger DOWN → delta negative
    expect(spinner()).toBeNull()

    el.dispatchEvent(touchEvent("touchend", 500))
    expect(reload).not.toHaveBeenCalled()
  })

  it("does not spawn a spinner on a bare touch that never pulls", async () => {
    await build({ enabled: true })
    fakeGeometry(el, { atBottom: true })
    appendSpinnerTemplate()

    el.dispatchEvent(touchEvent("touchstart", 700))
    el.dispatchEvent(touchEvent("touchend", 700)) // no movement
    expect(spinner()).toBeNull()
  })
})
