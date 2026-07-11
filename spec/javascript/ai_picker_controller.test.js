// spec/javascript/ai_picker_controller.test.js
//
// Vitest (jsdom) suite for pito--ai-picker: the multi-provider /config ai
// overlay. All markup is server-rendered; the controller navigates rows and
// persists through PATCH /settings/ai. fetch is stubbed per example.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import AiPickerController from "controllers/pito/ai_picker_controller"

const T = "data-pito--ai-picker-target"

// jsdom does not implement scrollIntoView — #select calls it on every move.
Element.prototype.scrollIntoView = vi.fn()

function modelRow(provider, value, marker = "") {
  return `<button type="button" ${T}="row" data-row-type="model" data-provider="${provider}" data-value="${value}"><span>${marker}</span><span>${value}</span></button>`
}

function providerGroup(provider, { keyed }) {
  return `
    <div data-section="provider" data-provider="${provider}">
      <span ${T}="keyChip" data-provider="${provider}">${keyed ? "key ●●●●" : "no key"}</span>
      <button type="button" ${T}="row" data-row-type="connect" data-provider="${provider}" data-value="" ${keyed ? "hidden" : ""}><span>+</span></button>
      <input type="password" ${T}="keyInput" data-provider="${provider}" hidden
             data-action="keydown.enter->pito--ai-picker#saveKey">
    </div>`
}

describe("pito--ai-picker controller", () => {
  let app, root, ctrl, fetchMock

  async function build() {
    document.head.innerHTML = '<meta name="csrf-token" content="tok">'
    fetchMock = vi.fn(async () => ({ ok: true, status: 200 }))
    global.fetch = fetchMock

    root = document.createElement("div")
    root.setAttribute("data-controller", "pito--ai-picker")
    root.setAttribute("data-pito--ai-picker-endpoint-value", "/settings/ai")
    root.innerHTML = `
      <input type="text" ${T}="search" data-action="input->pito--ai-picker#filter">
      <div ${T}="list">
        <button type="button" ${T}="row" data-row-type="effort" data-provider="alpha" data-value="off">
          <span></span><span ${T}="effortValue">model default</span>
        </button>
        ${providerGroup("alpha", { keyed: true })}
        ${modelRow("alpha", "m-1")}
        ${modelRow("alpha", "m-2")}
        ${providerGroup("beta", { keyed: false })}
        ${modelRow("beta", "b-1")}
      </div>
      <div ${T}="status"></div>`
    document.body.appendChild(root)

    app = Application.start()
    app.register("pito--ai-picker", AiPickerController)
    await Promise.resolve()
    ctrl = app.getControllerForElementAndIdentifier(root, "pito--ai-picker")
  }

  beforeEach(async () => { await build() })

  afterEach(async () => {
    vi.restoreAllMocks()
    // Explicitly abort THIS test's window keydown listener before anything
    // else: a stale capture-phase listener would stopImmediatePropagation-
    // starve the next test's controller (app.stop() does not reliably fire
    // disconnect callbacks). disconnect() is idempotent, so Stimulus firing
    // it again on DOM teardown is harmless.
    ctrl?.disconnect()
    await app.stop()
    await new Promise((r) => setTimeout(r, 10))
    document.body.innerHTML = ""
    document.head.innerHTML = ""
  })

  const key = (k, opts = {}) =>
    window.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, ...opts }))

  const rows = () => Array.from(root.querySelectorAll(`[${T}="row"]`))
  const selected = () => rows().find((r) => r.classList.contains("pito-palette-selected"))
  const lastBody = () => JSON.parse(fetchMock.mock.calls.at(-1)[1].body)

  // Deterministic, BOUNDED navigation: clamp the selection to the top row,
  // then walk down until the target is selected. Fails the example instead of
  // spinning forever when the target is unreachable (unbounded while-loops
  // here used to allocate keydown events until the vitest worker OOM'd).
  const selectRow = (target) => {
    const count = rows().filter((r) => !r.hidden).length
    for (let i = 0; i < count; i++) key("ArrowUp")
    for (let i = 0; i < count && selected() !== target; i++) key("ArrowDown")
    expect(selected()).toBe(target)
  }

  it("moves the selection with arrows and picks a model with enter", async () => {
    // visible rows: effort, alpha m-1, alpha m-2, beta connect, beta b-1
    const target = rows().find((r) => r.dataset.value === "m-1")
    selectRow(target)

    key("Enter")
    await Promise.resolve()

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(lastBody()).toEqual({ provider: "alpha", model: "m-1" })
    await Promise.resolve()
    expect(target.querySelector("span").textContent).toBe("●")
  })

  it("connect row reveals the provider's key input; enter saves the key and flips the chip", async () => {
    const connect = rows().find((r) => r.dataset.rowType === "connect" && r.dataset.provider === "beta")
    selectRow(connect)
    key("Enter")

    const input = root.querySelector(`[${T}="keyInput"][data-provider="beta"]`)
    expect(input.hidden).toBe(false)

    input.value = "sk-x"
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    await Promise.resolve(); await Promise.resolve()

    expect(lastBody()).toEqual({ provider: "beta", api_key: "sk-x" })
    expect(input.hidden).toBe(true)
    expect(root.querySelector(`[${T}="keyChip"][data-provider="beta"]`).textContent).toContain("●●●●")
  })

  it("ctrl+x clears the selected row's provider key and restores its connect row", async () => {
    const target = rows().find((r) => r.dataset.value === "m-2")
    selectRow(target)

    key("x", { ctrlKey: true })
    await Promise.resolve(); await Promise.resolve()

    expect(lastBody()).toEqual({ provider: "alpha", clear_key: true })
    expect(root.querySelector(`[${T}="keyChip"][data-provider="alpha"]`).textContent).toContain("no key")
    const connect = rows().find((r) => r.dataset.rowType === "connect" && r.dataset.provider === "alpha")
    expect(connect.hidden).toBe(false)
  })

  it("ctrl+f toggles the selected model as a favorite", async () => {
    const target = rows().find((r) => r.dataset.value === "m-1")
    selectRow(target)

    key("f", { ctrlKey: true })
    await Promise.resolve()

    expect(lastBody()).toEqual({ favorite: "alpha/m-1" })
  })

  it("enter on the effort row cycles off → low", async () => {
    const effort = rows().find((r) => r.dataset.rowType === "effort")
    selectRow(effort)

    key("Enter")
    await Promise.resolve(); await Promise.resolve()

    expect(lastBody()).toEqual({ effort: "low" })
    expect(root.querySelector(`[${T}="effortValue"]`).textContent).toBe("low")
  })

  it("filters model rows by provider/id substring, leaving other row types alone", () => {
    const search = root.querySelector(`[${T}="search"]`)
    search.value = "b-"
    search.dispatchEvent(new Event("input", { bubbles: true }))

    expect(rows().find((r) => r.dataset.value === "m-1").hidden).toBe(true)
    expect(rows().find((r) => r.dataset.value === "b-1").hidden).toBe(false)
    expect(rows().find((r) => r.dataset.rowType === "effort").hidden).toBe(false)
  })

  it("escape removes the overlay", () => {
    key("Escape")
    expect(document.getElementById("pito-ai-picker")).toBeNull()
    expect(document.body.contains(root)).toBe(false)
  })

  it("escape inside an open key input backs out to the list first; a second escape closes", () => {
    const connect = rows().find((r) => r.dataset.rowType === "connect" && r.dataset.provider === "beta")
    selectRow(connect)
    key("Enter") // reveals + focuses the key input

    const input = root.querySelector(`[${T}="keyInput"][data-provider="beta"]`)
    input.value = "half-pasted"
    key("Escape")

    expect(document.body.contains(root)).toBe(true) // still open
    expect(input.hidden).toBe(true)
    expect(input.value).toBe("")

    key("Escape")
    expect(document.body.contains(root)).toBe(false)
  })

  it("flashes 'unknown model' on a 422 and moves no marker", async () => {
    fetchMock.mockResolvedValueOnce({ ok: false, status: 422 })
    const target = rows().find((r) => r.dataset.value === "m-1")
    selectRow(target)

    key("Enter")
    await Promise.resolve(); await Promise.resolve()

    expect(root.querySelector(`[${T}="status"]`).textContent).toBe("unknown model")
    expect(target.querySelector("span").textContent).toBe("")
  })
})
