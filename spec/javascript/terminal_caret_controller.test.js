// spec/javascript/terminal_caret_controller.test.js
//
// Tests for the pito--terminal-caret Stimulus controller, focused on the
// INPUT-MODE block visibility being robust to focus timing.
//
// The five single-line inputs (IGDB import search, game picker search, video
// picker search, conversation rename, ctrl+k palette) are focused by their OWN
// sibling controllers, whose focus() can land around the caret controller's
// connect — beating both the one-time `document.activeElement` check and, in some
// orderings, the focus listener. The controller therefore re-asserts visibility
// from the live activeElement on the next microtask AND animation frame: whenever
// the field is the active element the block must be visible, without depending on
// having observed the focus transition. Blur still hides it (only the focused
// input shows a block), and the always-visible textarea/chatbox path is unchanged.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import TerminalCaretController from "controllers/pito/terminal_caret_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

function buildInput({ value = "", placeholder = "" } = {}) {
  const wrap = document.createElement("div")
  wrap.className = "relative"
  wrap.setAttribute("data-controller", "pito--terminal-caret")

  const field = document.createElement("input")
  field.type = "text"
  field.value = value
  if (placeholder) field.placeholder = placeholder
  field.className = "pito-caret-input"
  field.setAttribute("data-pito--terminal-caret-target", "field")

  const block = document.createElement("span")
  block.className = "terminal-caret"
  block.setAttribute("data-pito--terminal-caret-target", "block")
  block.setAttribute("aria-hidden", "true")

  wrap.appendChild(field)
  wrap.appendChild(block)
  return { wrap, field, block }
}

function buildTextarea({ value = "" } = {}) {
  const wrap = document.createElement("div")
  wrap.setAttribute("data-controller", "pito--terminal-caret")

  const field = document.createElement("textarea")
  field.value = value
  field.setAttribute("data-pito--terminal-caret-target", "field")

  const block = document.createElement("span")
  block.className = "terminal-caret"
  block.setAttribute("data-pito--terminal-caret-target", "block")
  block.setAttribute("aria-hidden", "true")

  wrap.appendChild(field)
  wrap.appendChild(block)
  return { wrap, field, block }
}

// Wait one animation frame (the controller's post-connect resync runs here).
function rAFTick() {
  return new Promise((resolve) => requestAnimationFrame(resolve))
}

// Wait one event-loop turn (lets Stimulus connect controllers).
function tick() {
  return new Promise((r) => setTimeout(r, 0))
}

// ── Suite ──────────────────────────────────────────────────────────────────────

describe("pito--terminal-caret controller (input-mode visibility)", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--terminal-caret", TerminalCaretController)
  })

  afterEach(async () => {
    if (app) await app.stop()
    document.body.innerHTML = ""
  })

  it("shows the block when the field is already focused at connect", async () => {
    const { wrap, field, block } = buildInput({ placeholder: "Search…" })
    document.body.appendChild(wrap)
    // Sibling controller focuses synchronously, before the caret controller connects.
    field.focus()
    await tick() // Stimulus connects with the field already focused.
    expect(document.activeElement).toBe(field)
    expect(block.hasAttribute("hidden")).toBe(false)
  })

  it("shows the block when the field is focused immediately after connect", async () => {
    const { wrap, field, block } = buildInput()
    document.body.appendChild(wrap)
    await tick() // connect: field not focused yet → block hidden.
    expect(block.hasAttribute("hidden")).toBe(true)

    field.focus() // sibling-controller focus lands after connect.
    await rAFTick()
    expect(block.hasAttribute("hidden")).toBe(false)
  })

  it("re-asserts visibility from activeElement even if the focus event is missed (race fix)", async () => {
    const { wrap, field, block } = buildInput()
    document.body.appendChild(wrap)
    await tick() // connect schedules the microtask + animation-frame resync.

    // Simulate the sibling-controller race: the field becomes the active element
    // around connect, but the block is left in the stale "no caret" hidden state
    // (the focus transition was never reflected onto the block).
    field.focus()
    block.setAttribute("hidden", "")

    await rAFTick() // the connect-scheduled resync runs here.
    // The fix re-reads document.activeElement and shows the block; without the
    // resync the block would stay hidden (the reported invisible-cursor bug).
    expect(document.activeElement).toBe(field)
    expect(block.hasAttribute("hidden")).toBe(false)
  })

  it("hides the block on blur (only the focused input shows a caret)", async () => {
    const { wrap, field, block } = buildInput()
    document.body.appendChild(wrap)
    await tick()

    field.focus()
    await rAFTick()
    expect(block.hasAttribute("hidden")).toBe(false)

    field.blur()
    expect(block.hasAttribute("hidden")).toBe(true)
  })

  it("keeps the block hidden after connect when nothing is focused", async () => {
    const { wrap, block } = buildInput()
    document.body.appendChild(wrap)
    await tick()
    await rAFTick() // resync runs; field still not the active element.
    expect(block.hasAttribute("hidden")).toBe(true)
  })

  it("leaves the textarea/chatbox block always visible (never hidden)", async () => {
    const { wrap, field, block } = buildTextarea({ value: "hi" })
    document.body.appendChild(wrap)
    await tick()
    await rAFTick()
    // Multi-line mode never toggles `hidden` — the chatbox caret is always present.
    expect(block.hasAttribute("hidden")).toBe(false)

    field.focus()
    await rAFTick()
    expect(block.hasAttribute("hidden")).toBe(false)

    field.blur()
    expect(block.hasAttribute("hidden")).toBe(false)
  })
})
