// spec/javascript/fps_overlay_controller.test.js
//
// Vitest suite for pito--fps-overlay Stimulus controller.
//
// The controller delegates a single `keydown` listener on `document` (same
// document-level shape as pito--anchor-jump / pito--scroll-nav). On F9 it
// toggles the `hidden` class on `this.element` (the `.pito-fps-overlay`
// wrapper) — unless focus is currently inside an <input>, <textarea>, or any
// contenteditable element, in which case the keydown falls through untouched
// (the chatbox owns typing) and nothing is toggled or prevented.
//
// Covers:
//   • F9 toggles `hidden` off, then a second F9 puts it back on
//   • A handled F9 calls preventDefault()
//   • Focus guard: <input> focused → no-op (still hidden, not prevented)
//   • Focus guard: <textarea> focused → no-op
//   • Focus guard: isContentEditable element focused → no-op (jsdom does not
//     derive isContentEditable from the attribute, so it is set directly)
//   • Other keys (F8, Escape) do nothing
//   • After the element is removed and the controller disconnects, F9 no
//     longer throws or mutates anything (listener detached)

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import FpsOverlayController from "controllers/pito/fps_overlay_controller"

// ── DOM scaffold ─────────────────────────────────────────────────────────────

// The controller listens on `document`, not `this.element` — any element
// carrying the data-controller attribute is enough to connect it. Mirrors the
// component's `.pito-fps-overlay` wrapper, starting hidden like the real one.
function buildScaffold({ hidden = true } = {}) {
  const el = document.createElement("div")
  el.setAttribute("data-controller", "pito--fps-overlay")
  el.className = "pito-fps-overlay"
  if (hidden) el.classList.add("hidden")
  document.body.appendChild(el)
  return el
}

function pressKey(key, opts = {}) {
  const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, ...opts })
  document.dispatchEvent(event)
  return event
}

function tick(ms = 20) {
  return new Promise((r) => setTimeout(r, ms))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--fps-overlay controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--fps-overlay", FpsOverlayController)
  })

  afterEach(async () => {
    // Stimulus stop() only pauses observation — it never disconnects live
    // controllers, so the document-delegated keydown listener would leak
    // into the next test. Remove the controller's element FIRST and let the
    // MutationObserver deliver the disconnect before stopping the app.
    document.body.innerHTML = ""
    await tick(0)
    await app.stop()
    vi.restoreAllMocks()
  })

  it("F9 toggles the hidden class off, and a second F9 puts it back", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    pressKey("F9")
    expect(el.classList.contains("hidden")).toBe(false)

    pressKey("F9")
    expect(el.classList.contains("hidden")).toBe(true)
  })

  it("calls preventDefault on a handled F9", async () => {
    buildScaffold({ hidden: true })
    await tick()

    const event = pressKey("F9")
    expect(event.defaultPrevented).toBe(true)
  })

  it("does nothing while focus is inside an <input>", async () => {
    const el = buildScaffold({ hidden: true })
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.focus()
    await tick()

    const event = pressKey("F9")

    expect(el.classList.contains("hidden")).toBe(true)
    expect(event.defaultPrevented).toBe(false)
  })

  it("does nothing while focus is inside a <textarea>", async () => {
    const el = buildScaffold({ hidden: true })
    const textarea = document.createElement("textarea")
    document.body.appendChild(textarea)
    textarea.focus()
    await tick()

    const event = pressKey("F9")

    expect(el.classList.contains("hidden")).toBe(true)
    expect(event.defaultPrevented).toBe(false)
  })

  it("does nothing while focus is inside a contenteditable element", async () => {
    const el = buildScaffold({ hidden: true })
    const editable = document.createElement("div")
    // A plain <div> has no tabindex, so jsdom won't focus() it — give it one
    // so document.activeElement actually becomes this element.
    editable.setAttribute("tabindex", "0")
    // jsdom does not derive isContentEditable from the contenteditable
    // attribute, so the property is set directly on the node.
    Object.defineProperty(editable, "isContentEditable", { value: true })
    document.body.appendChild(editable)
    editable.focus()
    await tick()

    const event = pressKey("F9")

    expect(el.classList.contains("hidden")).toBe(true)
    expect(event.defaultPrevented).toBe(false)
  })

  it("does nothing for other keys (F8, Escape)", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    const f8 = pressKey("F8")
    expect(el.classList.contains("hidden")).toBe(true)
    expect(f8.defaultPrevented).toBe(false)

    const esc = pressKey("Escape")
    expect(el.classList.contains("hidden")).toBe(true)
    expect(esc.defaultPrevented).toBe(false)
  })

  it("stops reacting to F9 after the element is removed and the controller disconnects", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    document.body.removeChild(el)
    await tick()

    expect(() => pressKey("F9")).not.toThrow()
    // The removed element is untouched — it was never re-attached or mutated.
    expect(el.classList.contains("hidden")).toBe(true)
  })
})
