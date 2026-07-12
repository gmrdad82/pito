// spec/javascript/selection_scope_controller.test.js
//
// Vitest suite for pito--selection-scope: the clamp that re-scopes the mobile
// context menu's "Select all" to the message the long-press started in.
//
// Strategy: mount the real controller on jsdom, stub document.getSelection
// with a controllable fake (jsdom's real Selection is too limited), and fire
// `selectionchange` events. The fake records selectAllChildren calls — a
// clamp is exactly one such call.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import SelectionScopeController from "../../app/javascript/controllers/pito/selection_scope_controller"

describe("pito--selection-scope", () => {
  let app, fakeSelection

  const fireSelectionChange = () => {
    document.dispatchEvent(new Event("selectionchange"))
  }

  const setSelection = ({ anchorNode, focusNode, contains = [], collapsed = false }) => {
    fakeSelection.anchorNode = anchorNode
    fakeSelection.focusNode = focusNode
    fakeSelection.isCollapsed = collapsed
    fakeSelection.rangeCount = collapsed ? 0 : 1
    fakeSelection.containsNode = vi.fn((node) => contains.includes(node))
    fireSelectionChange()
  }

  beforeEach(async () => {
    document.body.innerHTML = `
      <div id="scrollback" data-controller="pito--selection-scope">
        <div id="msg-1" data-scrollback-message><span id="text-1">first message</span></div>
        <div id="msg-2" data-scrollback-message><span id="text-2">second message</span></div>
      </div>`
    fakeSelection = { selectAllChildren: vi.fn(), containsNode: vi.fn(() => false), rangeCount: 0, isCollapsed: true }
    vi.spyOn(document, "getSelection").mockImplementation(() => fakeSelection)

    app = Application.start()
    app.register("pito--selection-scope", SelectionScopeController)
    await new Promise((resolve) => setTimeout(resolve, 0))
  })

  afterEach(async () => {
    // Wipe the DOM while the app still OBSERVES (that's what fires
    // disconnect() and detaches the document-level listeners), tick so the
    // mutation delivers, then stop — else a leaked controller double-clamps
    // the next test.
    document.body.innerHTML = ""
    await new Promise((resolve) => setTimeout(resolve, 0))
    await app.stop()
    vi.restoreAllMocks()
  })

  it("intercepts selectstart OUTSIDE a message flash-free when a message selection is active", () => {
    const text1 = document.getElementById("text-1")
    setSelection({ anchorNode: text1, focusNode: text1 }) // remembered

    const event = new Event("selectstart", { bubbles: true, cancelable: true })
    Object.defineProperty(event, "target", { value: document.getElementById("scrollback") })
    document.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(fakeSelection.selectAllChildren).toHaveBeenCalledWith(document.getElementById("msg-1"))
  })

  it("never intercepts a selectstart INSIDE a message (fresh drags stay native)", () => {
    const text1 = document.getElementById("text-1")
    setSelection({ anchorNode: text1, focusNode: text1 })

    const event = new Event("selectstart", { bubbles: true, cancelable: true })
    Object.defineProperty(event, "target", { value: document.getElementById("text-2") })
    document.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
    expect(fakeSelection.selectAllChildren).not.toHaveBeenCalled()
  })

  it("clamps a select-all back to the long-pressed message", () => {
    const msg = document.getElementById("msg-1")
    const text = document.getElementById("text-1")

    // The long-press word selection lives inside msg-1 → remembered.
    setSelection({ anchorNode: text, focusNode: text })
    // Native Select all: anchor jumps to the container, everything selected.
    setSelection({
      anchorNode: document.getElementById("scrollback"),
      focusNode: document.getElementById("text-2"),
      contains: [ msg ]
    })

    expect(fakeSelection.selectAllChildren).toHaveBeenCalledTimes(1)
    expect(fakeSelection.selectAllChildren).toHaveBeenCalledWith(msg)
  })

  it("never clamps a manual drag out of the message (anchor stays put)", () => {
    const text1 = document.getElementById("text-1")

    setSelection({ anchorNode: text1, focusNode: text1 })
    // Drag into msg-2: anchor still in msg-1 (the remembered message).
    setSelection({
      anchorNode: text1,
      focusNode: document.getElementById("text-2"),
      contains: [ document.getElementById("msg-1") ]
    })

    expect(fakeSelection.selectAllChildren).not.toHaveBeenCalled()
  })

  it("leaves selections alone when no in-message selection was remembered", () => {
    setSelection({
      anchorNode: document.getElementById("scrollback"),
      focusNode: document.getElementById("text-2"),
      contains: [ document.getElementById("msg-1"), document.getElementById("msg-2") ]
    })

    expect(fakeSelection.selectAllChildren).not.toHaveBeenCalled()
  })

  it("leaves selections alone when they don't contain the remembered message", () => {
    const text1 = document.getElementById("text-1")
    setSelection({ anchorNode: text1, focusNode: text1 })
    // A fresh selection elsewhere that doesn't swallow msg-1.
    setSelection({
      anchorNode: document.getElementById("scrollback"),
      focusNode: document.getElementById("text-2"),
      contains: []
    })

    expect(fakeSelection.selectAllChildren).not.toHaveBeenCalled()
  })

  it("ignores collapsed selections", () => {
    setSelection({ anchorNode: null, focusNode: null, collapsed: true })
    expect(fakeSelection.selectAllChildren).not.toHaveBeenCalled()
  })
})
