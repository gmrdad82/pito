// spec/javascript/chatbox_hints_controller.test.js
//
// Tests for pito--chatbox-hints (item 10): single-row meta hints chosen from
// focus + the leading verb/noun typed in the chatbox textarea.
//
// Matrix:
//   unfocused                                    → chatHint (m)
//   focused + `list` + vids/games noun           → channelHint (ctrl+space)
//   focused + `analyze`                          → periodHint (ctrl+space)
//   focused + empty / other verb                 → nothing
//
// Both cyclers share ONE physical binding (owner 2026-07-24: shift+tab/
// shift+space retired, unified on ctrl+space) — chat_form_controller tells
// them apart by which of channelHint/periodHint is visible.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import ChatboxHintsController from "controllers/pito/chatbox_hints_controller"

function buildChatbox() {
  const box = document.createElement("div")
  box.id = "pito-chatbox"
  box.setAttribute("data-controller", "pito--chatbox-hints")

  const chatHint = mkSpan(box, "chatHint")
  const channelHint = mkSpan(box, "channelHint")
  const periodHint = mkSpan(box, "periodHint")

  const field = document.createElement("textarea")
  box.appendChild(field)

  document.body.appendChild(box)
  return { box, chatHint, channelHint, periodHint, field }
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
    const { chatHint, channelHint, periodHint } = buildChatbox()
    await tick()
    expect(visible(chatHint)).toBe(true)
    expect(visible(channelHint)).toBe(false)
    expect(visible(periodHint)).toBe(false)
  })

  it("focused + empty → nothing", async () => {
    const { chatHint, channelHint, periodHint } = buildChatbox()
    await tick()
    focus("")
    expect(visible(chatHint)).toBe(false)
    expect(visible(channelHint)).toBe(false)
    expect(visible(periodHint)).toBe(false)
  })

  it("focused + `list vids` → channel hint", async () => {
    const { channelHint, periodHint, chatHint } = buildChatbox()
    await tick()
    focus("list vids")
    expect(visible(channelHint)).toBe(true)
    expect(visible(periodHint)).toBe(false)
    expect(visible(chatHint)).toBe(false)
  })

  it("focused + `list games rpg` → channel hint (noun anywhere after verb)", async () => {
    const { channelHint } = buildChatbox()
    await tick()
    focus("list games rpg")
    expect(visible(channelHint)).toBe(true)
  })

  it("focused + `ls videos` (aliases) → channel hint", async () => {
    const { channelHint } = buildChatbox()
    await tick()
    focus("ls videos")
    expect(visible(channelHint)).toBe(true)
  })

  it("focused + `list channels` → nothing (channels noun isn't vids/games)", async () => {
    const { channelHint, periodHint, chatHint } = buildChatbox()
    await tick()
    focus("list channels")
    expect(visible(channelHint)).toBe(false)
    expect(visible(periodHint)).toBe(false)
    expect(visible(chatHint)).toBe(false)
  })

  it("focused + `analyze` → period hint", async () => {
    const { periodHint, channelHint } = buildChatbox()
    await tick()
    focus("analyze channel")
    expect(visible(periodHint)).toBe(true)
    expect(visible(channelHint)).toBe(false)
  })

  it("focused + `stats` (alias) → period hint", async () => {
    const { periodHint } = buildChatbox()
    await tick()
    focus("stats vids")
    expect(visible(periodHint)).toBe(true)
  })

  it("focused + other verb (`show game`) → nothing", async () => {
    const { channelHint, periodHint, chatHint } = buildChatbox()
    await tick()
    focus("show game 5")
    expect(visible(channelHint)).toBe(false)
    expect(visible(periodHint)).toBe(false)
    expect(visible(chatHint)).toBe(false)
  })

  it("losing focus from `list vids` falls back to the m hint", async () => {
    const { chatHint, channelHint } = buildChatbox()
    await tick()
    focus("list vids")
    expect(visible(channelHint)).toBe(true)
    blur()
    expect(visible(chatHint)).toBe(true)
    expect(visible(channelHint)).toBe(false)
  })

  it("never leaves both inline-flex and hidden on the same element", async () => {
    const { chatHint, channelHint, periodHint } = buildChatbox()
    await tick()
    for (const v of ["", "list vids", "analyze", "show game"]) {
      focus(v)
      for (const el of [chatHint, channelHint, periodHint]) {
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
