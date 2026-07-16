// spec/javascript/fps_overlay_controller.test.js
//
// Vitest suite for pito--fps-overlay Stimulus controller.
//
// The controller delegates a single `keydown` listener on `document` (same
// document-level shape as pito--anchor-jump / pito--scroll-nav). On CTRL+F9
// — and ONLY Ctrl+F9 (owner call: unmodified F9 is reserved for the
// operator's own tooling and must pass through untouched) — it toggles the
// `hidden` class on `this.element` (the `.pito-fps-overlay` wrapper),
// REGARDLESS of where focus currently is: it inserts no text, and pito's
// chatbox effectively always has focus in this chat-first UI, so an
// editable-target guard would make the toggle unreachable in practice.
// Alt+F9 and Meta+F9 are left alone for the OS/window manager.
//
// Covers:
//   • Ctrl+F9 toggles `hidden` off, then a second Ctrl+F9 puts it back
//   • A handled Ctrl+F9 calls preventDefault()
//   • Ctrl+F9 toggles even while an <input> has focus (the
//     chatbox-always-focused regression), and a second press hides it again
//   • Plain (unmodified) F9 does NOTHING — reserved for the operator
//   • Alt+F9 and Meta+F9 do nothing (left for the OS/window manager)
//   • Other keys (F8, Escape) do nothing
//   • After the element is removed and the controller disconnects, Ctrl+F9
//     no longer throws or mutates anything (listener detached)

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

  it("Ctrl+F9 toggles the hidden class off, and a second Ctrl+F9 puts it back", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    pressKey("F9", { ctrlKey: true })
    expect(el.classList.contains("hidden")).toBe(false)

    pressKey("F9", { ctrlKey: true })
    expect(el.classList.contains("hidden")).toBe(true)
  })

  it("calls preventDefault on a handled Ctrl+F9", async () => {
    buildScaffold({ hidden: true })
    await tick()

    const event = pressKey("F9", { ctrlKey: true })
    expect(event.defaultPrevented).toBe(true)
  })

  it("toggles even while an <input> has focus (the chatbox-always-focused regression), and a second press hides it again", async () => {
    const el = buildScaffold({ hidden: true })
    const input = document.createElement("input")
    document.body.appendChild(input)
    input.focus()
    await tick()

    const first = pressKey("F9", { ctrlKey: true })
    expect(el.classList.contains("hidden")).toBe(false)
    expect(first.defaultPrevented).toBe(true)

    const second = pressKey("F9", { ctrlKey: true })
    expect(el.classList.contains("hidden")).toBe(true)
    expect(second.defaultPrevented).toBe(true)
  })

  it("does NOTHING on plain (unmodified) F9 — reserved for the operator's own tooling", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    const event = pressKey("F9")
    expect(el.classList.contains("hidden")).toBe(true)
    expect(event.defaultPrevented).toBe(false)
  })

  it("does nothing for Alt+F9 or Meta+F9 (left for the OS/window manager)", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    const alt = pressKey("F9", { ctrlKey: true, altKey: true })
    expect(el.classList.contains("hidden")).toBe(true)
    expect(alt.defaultPrevented).toBe(false)

    const meta = pressKey("F9", { ctrlKey: true, metaKey: true })
    expect(el.classList.contains("hidden")).toBe(true)
    expect(meta.defaultPrevented).toBe(false)
  })

  it("does nothing for other keys (Ctrl+F8, Escape)", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    const f8 = pressKey("F8", { ctrlKey: true })
    expect(el.classList.contains("hidden")).toBe(true)
    expect(f8.defaultPrevented).toBe(false)

    const esc = pressKey("Escape")
    expect(el.classList.contains("hidden")).toBe(true)
    expect(esc.defaultPrevented).toBe(false)
  })

  it("stops reacting to Ctrl+F9 after the element is removed and the controller disconnects", async () => {
    const el = buildScaffold({ hidden: true })
    await tick()

    document.body.removeChild(el)
    await tick()

    expect(() => pressKey("F9", { ctrlKey: true })).not.toThrow()
    // The removed element is untouched — it was never re-attached or mutated.
    expect(el.classList.contains("hidden")).toBe(true)
  })
})
