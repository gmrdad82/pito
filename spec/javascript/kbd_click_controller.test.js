// spec/javascript/kbd_click_controller.test.js
//
// Tests for pito/kbd_click_controller.js
//
// Clicking a shortcut hint synthesizes the SAME keydown the real keyboard
// handlers listen for — on the chatbox textarea or on `document` depending on
// the shortcut. We assert the right event is dispatched for a few keys.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import KbdClickController from "controllers/pito/kbd_click_controller"

function buildHint(keyValue) {
  document.body.innerHTML = `
    <textarea data-pito--chat-form-target="inputField"></textarea>
    <span
      data-controller="pito--kbd-click"
      data-pito--kbd-click-key-value="${keyValue}"
      data-action="mousedown->pito--kbd-click#hold click->pito--kbd-click#fire"
    >${keyValue}</span>
  `
  return document.querySelector("span[data-controller='pito--kbd-click']")
}

describe("KbdClickController", () => {
  let app

  beforeEach(async () => {
    app = Application.start()
    app.register("pito--kbd-click", KbdClickController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("ctrl+k dispatches a Ctrl+K keydown on document", async () => {
    const hint = buildHint("ctrl+k")
    await Promise.resolve()

    const handler = vi.fn()
    document.addEventListener("keydown", handler)

    hint.click()

    expect(handler).toHaveBeenCalledTimes(1)
    const e = handler.mock.calls[0][0]
    expect(e.key).toBe("k")
    expect(e.ctrlKey).toBe(true)
  })

  it("Esc (case/alias normalized) dispatches an Escape keydown on document", async () => {
    const hint = buildHint("Esc")
    await Promise.resolve()

    const handler = vi.fn()
    document.addEventListener("keydown", handler)

    hint.click()

    expect(handler).toHaveBeenCalledTimes(1)
    expect(handler.mock.calls[0][0].key).toBe("Escape")
  })

  it("shift+tab dispatches a Shift+Tab keydown on the chatbox textarea WITHOUT focusing it", async () => {
    const hint = buildHint("shift+tab")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const onField = vi.fn()
    const onDoc = vi.fn()
    field.addEventListener("keydown", onField)
    document.addEventListener("keydown", onDoc)

    hint.click()

    expect(onField).toHaveBeenCalledTimes(1)
    const e = onField.mock.calls[0][0]
    expect(e.key).toBe("Tab")
    expect(e.shiftKey).toBe(true)
    expect(e.target).toBe(field)
    // bubbles to document too
    expect(onDoc).toHaveBeenCalledTimes(1)
    // focus must NOT have moved into the chatbox
    expect(document.activeElement).not.toBe(field)
  })

  it("shift+space dispatches a Shift+Space keydown on the chatbox textarea WITHOUT focusing it", async () => {
    const hint = buildHint("shift+space")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const onField = vi.fn()
    const onDoc = vi.fn()
    field.addEventListener("keydown", onField)
    document.addEventListener("keydown", onDoc)

    hint.click()

    expect(onField).toHaveBeenCalledTimes(1)
    const e = onField.mock.calls[0][0]
    expect(e.key).toBe(" ")
    expect(e.code).toBe("Space")
    expect(e.shiftKey).toBe(true)
    expect(e.target).toBe(field)
    // bubbles to document too
    expect(onDoc).toHaveBeenCalledTimes(1)
    // focus must NOT have moved into the chatbox
    expect(document.activeElement).not.toBe(field)
  })

  it("shift+r dispatches a Shift+R keydown on the chatbox textarea AND focuses it", async () => {
    const hint = buildHint("shift+r")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const onField = vi.fn()
    field.addEventListener("keydown", onField)

    hint.click()

    expect(onField).toHaveBeenCalledTimes(1)
    const e = onField.mock.calls[0][0]
    expect(e.key).toBe("R")
    expect(e.shiftKey).toBe(true)
    expect(document.activeElement).toBe(field)
  })

  it("tab dispatches a Tab keydown on the chatbox textarea AND focuses it", async () => {
    const hint = buildHint("tab")
    await Promise.resolve()

    const field = document.querySelector('[data-pito--chat-form-target="inputField"]')
    const onField = vi.fn()
    field.addEventListener("keydown", onField)

    hint.click()

    expect(onField).toHaveBeenCalledTimes(1)
    const e = onField.mock.calls[0][0]
    expect(e.key).toBe("Tab")
    expect(e.shiftKey).toBeFalsy()
    expect(document.activeElement).toBe(field)
  })

  it("cmd+k normalizes to the ctrl+k handler", async () => {
    const hint = buildHint("cmd+k")
    await Promise.resolve()

    const handler = vi.fn()
    document.addEventListener("keydown", handler)

    hint.click()

    expect(handler).toHaveBeenCalledTimes(1)
    const e = handler.mock.calls[0][0]
    expect(e.key).toBe("k")
    expect(e.ctrlKey).toBe(true)
  })

  it("does nothing for an unknown key-value", async () => {
    const hint = buildHint("totally-unknown")
    await Promise.resolve()

    const handler = vi.fn()
    document.addEventListener("keydown", handler)

    hint.click()

    expect(handler).not.toHaveBeenCalled()
  })

  it("mousedown#hold preventDefaults so the tap does not blur/steal focus from the chatbox", async () => {
    const hint = buildHint("shift+tab")
    await Promise.resolve()

    const ev = new MouseEvent("mousedown", { bubbles: true, cancelable: true })
    hint.dispatchEvent(ev)

    expect(ev.defaultPrevented).toBe(true)
  })

  it("click#fire stops propagation so an ancestor handler (chatbox focusField) never runs", async () => {
    document.body.innerHTML = `
      <div id="wrap">
        <textarea data-pito--chat-form-target="inputField"></textarea>
        <span data-controller="pito--kbd-click" data-pito--kbd-click-key-value="m"
              data-action="mousedown->pito--kbd-click#hold click->pito--kbd-click#fire">m</span>
      </div>
    `
    await Promise.resolve()

    const ancestor = vi.fn()
    document.getElementById("wrap").addEventListener("click", ancestor)

    document.querySelector("span[data-controller='pito--kbd-click']").click()

    expect(ancestor).not.toHaveBeenCalled()
  })
})
