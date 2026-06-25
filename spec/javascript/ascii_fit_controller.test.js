// spec/javascript/ascii_fit_controller.test.js
//
// Tests for pito--ascii-fit: uniformly scales `white-space: pre` ASCII blocks
// DOWN to fit the available width (never up), preserving alignment + keeping the
// text live. Desktop (fits) → untouched; narrow viewport → scaled.
//
// jsdom has no layout, so element widths/heights are mocked per-element, and
// ResizeObserver is stubbed (capturing its callback so a "resize" can be fired).

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import AsciiFitController from "controllers/pito/ascii_fit_controller"

// ── Helpers ───────────────────────────────────────────────────────────────────

function tick() {
  return new Promise((r) => setTimeout(r, 0))
}

// Mock the non-layout dimensions jsdom always reports as 0.
function setDims(el, { client, scroll, height }) {
  if (client !== undefined) Object.defineProperty(el, "clientWidth", { configurable: true, get: () => client })
  if (scroll !== undefined) Object.defineProperty(el, "scrollWidth", { configurable: true, get: () => scroll })
  if (height !== undefined) Object.defineProperty(el, "offsetHeight", { configurable: true, get: () => height })
}

let roCallbacks

describe("pito--ascii-fit controller", () => {
  let app

  beforeEach(() => {
    roCallbacks = []
    global.ResizeObserver = class {
      constructor(cb) { roCallbacks.push(cb) }
      observe() {}
      disconnect() {}
    }
    app = Application.start()
    app.register("pito--ascii-fit", AsciiFitController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
    delete global.ResizeObserver
  })

  // Wrapper (clientWidth = available) holding one <pre> (scrollWidth = natural).
  function mount({ available, natural, height = 100, origin } = {}) {
    const wrapper = document.createElement("div")
    wrapper.setAttribute("data-controller", "pito--ascii-fit")
    if (origin) wrapper.setAttribute("data-pito--ascii-fit-origin-value", origin)
    const pre = document.createElement("pre")
    wrapper.appendChild(pre)
    document.body.appendChild(wrapper)
    setDims(wrapper, { client: available })
    setDims(pre, { scroll: natural, height })
    return { wrapper, pre }
  }

  it("leaves the block untouched when it already fits (desktop, scale 1)", async () => {
    const { pre } = mount({ available: 800, natural: 400 })
    await tick()
    expect(pre.style.transform).toBe("")
    expect(pre.style.marginBottom).toBe("")
  })

  it("scales the block down to fit a narrow viewport", async () => {
    const { pre } = mount({ available: 300, natural: 400, height: 120 })
    await tick()
    expect(pre.style.transform).toBe("scale(0.75)")
    expect(pre.style.transformOrigin).toBe("top left")
    // Reclaims the gap the shrunk visual leaves: -height * (1 - scale) = -120 * 0.25.
    expect(pre.style.marginBottom).toBe("-30px")
  })

  it("anchors at top center when origin: center (keeps a centered logo centered)", async () => {
    const { pre } = mount({ available: 300, natural: 400, origin: "center" })
    await tick()
    expect(pre.style.transformOrigin).toBe("top center")
    expect(pre.style.transform).toBe("scale(0.75)")
  })

  it("fits a <pre> nested inside the controller element (message body case)", async () => {
    const wrapper = document.createElement("div")
    wrapper.setAttribute("data-controller", "pito--ascii-fit")
    const span = document.createElement("span")
    const pre = document.createElement("pre")
    span.appendChild(pre)
    wrapper.appendChild(span)
    document.body.appendChild(wrapper)
    setDims(wrapper, { client: 200 })
    setDims(pre, { scroll: 400, height: 80 })
    await tick()
    expect(pre.style.transform).toBe("scale(0.5)")
  })

  it("is a no-op when the wrapper holds no <pre> (e.g. a list table body)", async () => {
    const wrapper = document.createElement("div")
    wrapper.setAttribute("data-controller", "pito--ascii-fit")
    wrapper.innerHTML = "<span>no art here</span>"
    document.body.appendChild(wrapper)
    setDims(wrapper, { client: 200 })
    await tick()
    // Nothing to scale, nothing throws.
    expect(wrapper.querySelector("pre")).toBe(null)
  })

  it("restores 1:1 when the viewport widens back (re-fit on resize)", async () => {
    const { wrapper, pre } = mount({ available: 300, natural: 400, height: 120 })
    await tick()
    expect(pre.style.transform).toBe("scale(0.75)")

    // Widen past the natural width and fire the captured ResizeObserver callback.
    setDims(wrapper, { client: 800 })
    roCallbacks.forEach((cb) => cb())
    expect(pre.style.transform).toBe("")
    expect(pre.style.marginBottom).toBe("")
  })
})
