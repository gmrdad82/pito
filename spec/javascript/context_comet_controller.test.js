// Vitest for pito--context-comet: the context-bar lit-fuse grow.
import { Application } from "@hotwired/stimulus"
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import ContextCometController from "controllers/pito/context_comet_controller"

function stubLocalStorage() {
  const m = new Map()
  vi.stubGlobal("localStorage", {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
    clear: () => m.clear(),
  })
}

function mount(pct) {
  document.body.innerHTML = `
    <div id="pito-context-meter" data-controller="pito--context-comet"
         data-pito--context-comet-pct-value="${pct}">
      <div class="pito-context-meter__track">
        <div class="pito-context-meter__fill" data-pito--context-comet-target="fill"
             style="width: ${pct}%;"></div>
        <div class="pito-context-meter__comet" data-pito--context-comet-target="comet"></div>
      </div>
    </div>`
}

const tick = () => new Promise((r) => setTimeout(r, 10))

describe("pito--context-comet", () => {
  let app
  beforeEach(() => {
    stubLocalStorage()
    app = Application.start()
    app.register("pito--context-comet", ContextCometController)
  })
  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })

  it("first render stores the pct and does NOT light the comet", async () => {
    mount(40)
    await tick()
    expect(document.querySelector(".pito-context-meter__comet").classList.contains("is-lit")).toBe(false)
    expect(localStorage.getItem(`pito:ctx-pct:${location.pathname}`)).toBe("40")
  })

  it("lights the comet and starts the grow from the previous pct on an increase", async () => {
    localStorage.setItem(`pito:ctx-pct:${location.pathname}`, "40")
    mount(60)
    await tick()
    const comet = document.querySelector(".pito-context-meter__comet")
    const fill = document.querySelector(".pito-context-meter__fill")
    expect(comet.classList.contains("is-lit")).toBe(true)
    // the grow begins at the OLD edge (40%) and the head is parked there before
    // the rAF transition runs toward 60% (rAF timing isn't deterministic in jsdom).
    expect(fill.style.width).toBe("40%")
    expect(localStorage.getItem(`pito:ctx-pct:${location.pathname}`)).toBe("60")
  })

  it("does not light the comet when the pct did not increase", async () => {
    localStorage.setItem(`pito:ctx-pct:${location.pathname}`, "60")
    mount(60)
    await tick()
    expect(document.querySelector(".pito-context-meter__comet").classList.contains("is-lit")).toBe(false)
  })
})
