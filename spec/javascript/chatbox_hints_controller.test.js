// spec/javascript/chatbox_hints_controller.test.js
//
// Tests for pito--chatbox-hints (item 10): single-row meta hints chosen from
// focus + the leading verb/noun typed in the chatbox textarea.
//
// Matrix:
//   unfocused                                    → chatHint (m)
//   focused + `list` + vids/games noun           → shiftTabHint
//   focused + `analyze`                          → shiftSpaceHint
//   focused + empty / other verb                 → nothing

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import ChatboxHintsController from "controllers/pito/chatbox_hints_controller"

function buildChatbox() {
  const box = document.createElement("div")
  box.id = "pito-chatbox"
  box.setAttribute("data-controller", "pito--chatbox-hints")

  const chatHint = mkSpan(box, "chatHint")
  const shiftTabHint = mkSpan(box, "shiftTabHint")
  const shiftSpaceHint = mkSpan(box, "shiftSpaceHint")

  const field = document.createElement("textarea")
  box.appendChild(field)

  document.body.appendChild(box)
  return { box, chatHint, shiftTabHint, shiftSpaceHint, field }
}

function mkSpan(box, target) {
  const span = document.createElement("span")
  span.setAttribute("data-pito--chatbox-hints-target", target)
  span.className = "hidden"
  box.appendChild(span)
  return span
}

const visible = (el) => el.classList.contains("inline-flex") && !el.classList.contains("hidden")

function focus(value) {
  // Set the field text, then mark focused via the custom event and fire input.
  const field = document.querySelector("#pito-chatbox textarea")
  field.value = value
  document.dispatchEvent(new CustomEvent("pito:focus", { bubbles: true, detail: { focused: true } }))
  field.dispatchEvent(new Event("input", { bubbles: true }))
}

function blur() {
  document.dispatchEvent(new CustomEvent("pito:focus", { bubbles: true, detail: { focused: false } }))
}

const tick = () => new Promise((r) => setTimeout(r, 0))

describe("pito--chatbox-hints controller", () => {
  let app

  beforeEach(async () => {
    app = Application.start()
    app.register("pito--chatbox-hints", ChatboxHintsController)
    await tick()
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  it("shows the m hint when not focused", async () => {
    const { chatHint, shiftTabHint, shiftSpaceHint } = buildChatbox()
    await tick()
    expect(visible(chatHint)).toBe(true)
    expect(visible(shiftTabHint)).toBe(false)
    expect(visible(shiftSpaceHint)).toBe(false)
  })

  it("focused + empty → nothing", async () => {
    const { chatHint, shiftTabHint, shiftSpaceHint } = buildChatbox()
    await tick()
    focus("")
    expect(visible(chatHint)).toBe(false)
    expect(visible(shiftTabHint)).toBe(false)
    expect(visible(shiftSpaceHint)).toBe(false)
  })

  it("focused + `list vids` → shift+tab", async () => {
    const { shiftTabHint, shiftSpaceHint, chatHint } = buildChatbox()
    await tick()
    focus("list vids")
    expect(visible(shiftTabHint)).toBe(true)
    expect(visible(shiftSpaceHint)).toBe(false)
    expect(visible(chatHint)).toBe(false)
  })

  it("focused + `list games rpg` → shift+tab (noun anywhere after verb)", async () => {
    const { shiftTabHint } = buildChatbox()
    await tick()
    focus("list games rpg")
    expect(visible(shiftTabHint)).toBe(true)
  })

  it("focused + `ls videos` (aliases) → shift+tab", async () => {
    const { shiftTabHint } = buildChatbox()
    await tick()
    focus("ls videos")
    expect(visible(shiftTabHint)).toBe(true)
  })

  it("focused + `list channels` → nothing (channels noun isn't vids/games)", async () => {
    const { shiftTabHint, shiftSpaceHint, chatHint } = buildChatbox()
    await tick()
    focus("list channels")
    expect(visible(shiftTabHint)).toBe(false)
    expect(visible(shiftSpaceHint)).toBe(false)
    expect(visible(chatHint)).toBe(false)
  })

  it("focused + `analyze` → shift+space", async () => {
    const { shiftSpaceHint, shiftTabHint } = buildChatbox()
    await tick()
    focus("analyze channel")
    expect(visible(shiftSpaceHint)).toBe(true)
    expect(visible(shiftTabHint)).toBe(false)
  })

  it("focused + `stats` (alias) → shift+space", async () => {
    const { shiftSpaceHint } = buildChatbox()
    await tick()
    focus("stats vids")
    expect(visible(shiftSpaceHint)).toBe(true)
  })

  it("focused + other verb (`show game`) → nothing", async () => {
    const { shiftTabHint, shiftSpaceHint, chatHint } = buildChatbox()
    await tick()
    focus("show game 5")
    expect(visible(shiftTabHint)).toBe(false)
    expect(visible(shiftSpaceHint)).toBe(false)
    expect(visible(chatHint)).toBe(false)
  })

  it("losing focus from `list vids` falls back to the m hint", async () => {
    const { chatHint, shiftTabHint } = buildChatbox()
    await tick()
    focus("list vids")
    expect(visible(shiftTabHint)).toBe(true)
    blur()
    expect(visible(chatHint)).toBe(true)
    expect(visible(shiftTabHint)).toBe(false)
  })

  it("never leaves both inline-flex and hidden on the same element", async () => {
    const { chatHint, shiftTabHint, shiftSpaceHint } = buildChatbox()
    await tick()
    for (const v of ["", "list vids", "analyze", "show game"]) {
      focus(v)
      for (const el of [chatHint, shiftTabHint, shiftSpaceHint]) {
        expect(el.classList.contains("inline-flex") && el.classList.contains("hidden")).toBe(false)
      }
    }
  })

  it("no-ops on a row without the hint targets (start/reduced static m)", async () => {
    const box = document.createElement("div")
    box.id = "pito-chatbox"
    box.setAttribute("data-controller", "pito--chatbox-hints")
    document.body.appendChild(box)
    await tick()
    // No throw, nothing to toggle.
    document.dispatchEvent(new CustomEvent("pito:focus", { bubbles: true, detail: { focused: true } }))
    expect(true).toBe(true)
  })
})
