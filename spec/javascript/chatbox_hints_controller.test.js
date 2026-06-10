// spec/javascript/chatbox_hints_controller.test.js
//
// Tests for pito--chatbox-hints Stimulus controller.
//
// Covers:
//   - Initial state: suggestHint hidden, chatHint visible when no active focus
//   - pito:suggest(active:true) shows suggestHint; (active:false) hides it
//   - pito:focus(focused:true) hides chatHint; (focused:false) shows it
//   - focusin/focusout on elements inside #pito-chatbox updates focused state
//   - Inline-flex / hidden class swap (never both present together)
//   - disconnect removes all listeners

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import ChatboxHintsController from "controllers/pito/chatbox_hints_controller"

// ── Helpers ──────────────────────────────────────────────────────────────────

function buildChatbox() {
  const box = document.createElement("div")
  box.id = "pito-chatbox"
  box.setAttribute("data-controller", "pito--chatbox-hints")

  const suggestHint = document.createElement("span")
  suggestHint.setAttribute("data-pito--chatbox-hints-target", "suggestHint")
  suggestHint.className = "hidden"
  box.appendChild(suggestHint)

  const chatHint = document.createElement("span")
  chatHint.setAttribute("data-pito--chatbox-hints-target", "chatHint")
  chatHint.className = "hidden"
  box.appendChild(chatHint)

  const filterHints = document.createElement("span")
  filterHints.setAttribute("data-pito--chatbox-hints-target", "filterHints")
  filterHints.className = "hidden"
  box.appendChild(filterHints)

  // A focusable child to simulate focus events
  const input = document.createElement("input")
  box.appendChild(input)

  document.body.appendChild(box)
  return { box, suggestHint, chatHint, filterHints, input }
}

function fireCustomEvent(name, detail = {}) {
  document.dispatchEvent(new CustomEvent(name, { bubbles: true, detail }))
}

function fireFocusIn(target) {
  target.dispatchEvent(new FocusEvent("focusin", { bubbles: true }))
}

function fireFocusOut(target) {
  target.dispatchEvent(new FocusEvent("focusout", { bubbles: true }))
}

// Wait one rAF tick for the controller's requestAnimationFrame recheck.
function rAFTick() {
  return new Promise((resolve) => requestAnimationFrame(resolve))
}

// Wait one event-loop turn.
function tick() {
  return new Promise((r) => setTimeout(r, 0))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

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

  // ── Initial state ───────────────────────────────────────────────────────────

  it("hides suggestHint on connect (no suggest active)", async () => {
    const { suggestHint } = buildChatbox()
    await tick()
    expect(suggestHint.classList.contains("hidden")).toBe(true)
    expect(suggestHint.classList.contains("inline-flex")).toBe(false)
  })

  it("shows chatHint on connect when nothing inside chatbox is focused", async () => {
    const { chatHint } = buildChatbox()
    await tick()
    expect(chatHint.classList.contains("inline-flex")).toBe(true)
    expect(chatHint.classList.contains("hidden")).toBe(false)
  })

  // ── pito:suggest event ──────────────────────────────────────────────────────

  it("shows suggestHint when pito:suggest fires with active:true", async () => {
    const { suggestHint } = buildChatbox()
    await tick()
    fireCustomEvent("pito:suggest", { active: true })
    expect(suggestHint.classList.contains("inline-flex")).toBe(true)
    expect(suggestHint.classList.contains("hidden")).toBe(false)
  })

  it("hides suggestHint when pito:suggest fires with active:false", async () => {
    const { suggestHint } = buildChatbox()
    await tick()
    // Activate then deactivate
    fireCustomEvent("pito:suggest", { active: true })
    fireCustomEvent("pito:suggest", { active: false })
    expect(suggestHint.classList.contains("hidden")).toBe(true)
    expect(suggestHint.classList.contains("inline-flex")).toBe(false)
  })

  it("hides suggestHint when pito:suggest fires with no detail", async () => {
    const { suggestHint } = buildChatbox()
    await tick()
    fireCustomEvent("pito:suggest", { active: true })
    // Fire without detail — active is falsy
    document.dispatchEvent(new CustomEvent("pito:suggest", { bubbles: true }))
    expect(suggestHint.classList.contains("hidden")).toBe(true)
  })

  // ── pito:focus event ────────────────────────────────────────────────────────

  it("hides chatHint when pito:focus fires with focused:true", async () => {
    const { chatHint } = buildChatbox()
    await tick()
    fireCustomEvent("pito:focus", { focused: true })
    expect(chatHint.classList.contains("hidden")).toBe(true)
    expect(chatHint.classList.contains("inline-flex")).toBe(false)
  })

  it("shows chatHint when pito:focus fires with focused:false", async () => {
    const { chatHint } = buildChatbox()
    await tick()
    fireCustomEvent("pito:focus", { focused: true })
    fireCustomEvent("pito:focus", { focused: false })
    expect(chatHint.classList.contains("inline-flex")).toBe(true)
    expect(chatHint.classList.contains("hidden")).toBe(false)
  })

  // ── filterHints (shift+tab / shift+space) ⟺ focused (inverse of chatHint) ─────

  it("shows filterHints and hides chatHint when focused", async () => {
    const { filterHints, chatHint } = buildChatbox()
    await tick()
    fireCustomEvent("pito:focus", { focused: true })
    expect(filterHints.classList.contains("inline-flex")).toBe(true)
    expect(filterHints.classList.contains("hidden")).toBe(false)
    expect(chatHint.classList.contains("hidden")).toBe(true)
  })

  it("hides filterHints and shows chatHint when not focused (mutually exclusive)", async () => {
    const { filterHints, chatHint } = buildChatbox()
    await tick()
    fireCustomEvent("pito:focus", { focused: true })
    fireCustomEvent("pito:focus", { focused: false })
    expect(filterHints.classList.contains("hidden")).toBe(true)
    expect(filterHints.classList.contains("inline-flex")).toBe(false)
    expect(chatHint.classList.contains("inline-flex")).toBe(true)
    // never both visible at once
    expect(filterHints.classList.contains("inline-flex") && chatHint.classList.contains("inline-flex")).toBe(false)
  })

  // ── Class swap invariant ────────────────────────────────────────────────────

  it("never leaves both inline-flex and hidden on the same element", async () => {
    const { suggestHint, chatHint } = buildChatbox()
    await tick()

    const events = [
      ["pito:suggest", { active: true }],
      ["pito:suggest", { active: false }],
      ["pito:focus",   { focused: true }],
      ["pito:focus",   { focused: false }],
    ]
    for (const [name, detail] of events) {
      fireCustomEvent(name, detail)
      for (const el of [suggestHint, chatHint]) {
        expect(
          el.classList.contains("inline-flex") && el.classList.contains("hidden"),
          `${name}: ${el.dataset.pitoChatboxHintsTarget} has both classes`
        ).toBe(false)
      }
    }
  })

  // ── focusin / focusout native events ────────────────────────────────────────

  it("hides chatHint when an element inside #pito-chatbox gains focus", async () => {
    const { chatHint, input } = buildChatbox()
    await tick()
    // Simulate focus entering the chatbox
    Object.defineProperty(document, "activeElement", {
      get: () => input,
      configurable: true,
    })
    fireFocusIn(input)
    await rAFTick()
    expect(chatHint.classList.contains("hidden")).toBe(true)
  })

  it("shows chatHint when focus leaves #pito-chatbox", async () => {
    const { chatHint, input } = buildChatbox()
    await tick()
    // First focus inside
    Object.defineProperty(document, "activeElement", {
      get: () => input,
      configurable: true,
    })
    fireFocusIn(input)
    await rAFTick()
    // Now focus leaves
    Object.defineProperty(document, "activeElement", {
      get: () => document.body,
      configurable: true,
    })
    fireFocusOut(input)
    await rAFTick()
    expect(chatHint.classList.contains("inline-flex")).toBe(true)
  })

  // ── disconnect ───────────────────────────────────────────────────────────────

  it("removes pito:suggest listener on disconnect", async () => {
    const { box, suggestHint } = buildChatbox()
    await tick()
    // Disconnect the controller
    box.removeAttribute("data-controller")
    await tick()
    fireCustomEvent("pito:suggest", { active: true })
    // suggestHint should still be hidden (listener removed)
    expect(suggestHint.classList.contains("hidden")).toBe(true)
  })
})
