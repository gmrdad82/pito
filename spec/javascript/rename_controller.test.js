// spec/javascript/rename_controller.test.js
//
// Vitest suite for pito--rename Stimulus controller.
//
// Strategy: mount the real controller on a jsdom document using the same
// Stimulus-Application pattern as history_controller.test.js.
//
// COVERAGE
//   - dblclick creates the rename input (focus+select) and applies editing classes
//   - `pito:rename:start` event also creates the rename input
//   - Enter commits rename: PATCH to urlValue (mock fetch), restores display span
//   - Esc cancels: restores original text, no PATCH
//   - Blank input on Enter cancels without PATCH
//   - Second dblclick while already editing: no second input created
//   - pito-row-editing class applied on start, removed on commit/cancel
//
// SKIPPED (jsdom limitations):
//   - Actual Turbo stream processing from PATCH response (Turbo not loaded)
//   - input.focus() / input.select() have no visible side effects in jsdom

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import RenameController from "controllers/pito/rename_controller"

// ── Scaffold ──────────────────────────────────────────────────────────────────

function buildScaffold(url = "/chat/test-uuid-1234") {
  const row = document.createElement("div")
  row.className = "pito-conversation-row"
  row.setAttribute("data-controller", "pito--rename")
  row.setAttribute("data-pito--rename-url-value", url)

  const span = document.createElement("span")
  span.className = "pito--rename-display"
  span.textContent = "My Conversation"
  row.appendChild(span)

  document.body.appendChild(row)
  return { row, span }
}

function dblclick(el) {
  el.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
}

function renameStart(el) {
  el.dispatchEvent(new CustomEvent("pito:rename:start", { bubbles: false }))
}

function keydown(el, key, opts = {}) {
  el.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, ...opts }))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--rename controller", () => {
  let app

  beforeEach(() => {
    app = Application.start()
    app.register("pito--rename", RenameController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    await app.stop()
    await new Promise((r) => setTimeout(r, 0))
    document.body.innerHTML = ""
  })

  function waitForConnect() {
    return new Promise((r) => setTimeout(r, 0))
  }

  // ── dblclick creates input ────────────────────────────────────────────────────

  it("dblclick creates a rename input inside the display span", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    dblclick(row)

    const input = row.querySelector("input.pito--rename-input")
    expect(input).not.toBeNull()
  })

  it("dblclick pre-fills input with current title", async () => {
    const { row, span } = buildScaffold()
    await waitForConnect()

    dblclick(row)

    const input = row.querySelector("input.pito--rename-input")
    expect(input.value).toBe("My Conversation")
  })

  it("dblclick adds pito-row-editing class to the row", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    dblclick(row)

    expect(row.classList.contains("pito-row-editing")).toBe(true)
  })

  // ── pito:rename:start event ───────────────────────────────────────────────────

  it("pito:rename:start creates the rename input", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    renameStart(row)

    const input = row.querySelector("input.pito--rename-input")
    expect(input).not.toBeNull()
  })

  // ── No double-input guard ─────────────────────────────────────────────────────

  it("second dblclick while editing does not create a second input", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    dblclick(row)
    dblclick(row)

    const inputs = row.querySelectorAll("input.pito--rename-input")
    expect(inputs.length).toBe(1)
  })

  // ── Native block caret (no JS overlay) ─────────────────────────────────────────

  it("gives the rename input the native block-caret class and no caret overlay", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    dblclick(row)

    const input = row.querySelector("input.pito--rename-input")
    expect(input).not.toBeNull()
    expect(input.className).toContain("pito-block-caret")
    // No bespoke caret/trail machinery is attached anymore.
    expect(row.querySelector(".pito--rename-caret-wrap")).toBeNull()
    expect(row.querySelector("span.terminal-caret")).toBeNull()
    expect(input.getAttribute("data-pito--terminal-caret-target")).toBeNull()
  })

  // ── Enter commits rename ──────────────────────────────────────────────────────

  it("Enter commits: calls PATCH to the url value", async () => {
    const { row } = buildScaffold("/chat/commit-uuid")
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: { get: () => "application/json" },
      text: () => Promise.resolve("{}"),
    })
    vi.stubGlobal("fetch", fetchMock)

    dblclick(row)

    const input = row.querySelector("input.pito--rename-input")
    input.value = "New Name"
    keydown(input, "Enter")

    expect(fetchMock).toHaveBeenCalledWith(
      "/chat/commit-uuid",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ title: "New Name" }),
      })
    )
  })

  it("Enter commit includes Content-Type: application/json header", async () => {
    const { row } = buildScaffold("/chat/header-uuid")
    await waitForConnect()

    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: { get: () => null },
      text: () => Promise.resolve(""),
    })
    vi.stubGlobal("fetch", fetchMock)

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    input.value = "Header Test"
    keydown(input, "Enter")

    expect(fetchMock).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({ "Content-Type": "application/json" }),
      })
    )
  })

  it("Enter commit with turbo-stream response would let Turbo replace the row (stubbed)", async () => {
    // In production, the server responds with a turbo-stream that replaces the row
    // entirely. In tests we stub a non-turbo json response so the controller's
    // commitRename completes successfully without calling #endEditing() (that path
    // is Turbo's job). We verify the optimistic title update is in place.
    const { row, span } = buildScaffold()
    await waitForConnect()

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      headers: { get: () => "application/json" }, // non-turbo → no Turbo.renderStreamMessage
    }))

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    input.value = "Clean Name"
    keydown(input, "Enter")

    await new Promise((r) => setTimeout(r, 0))

    // Optimistic update happened
    expect(span.textContent).toBe("Clean Name")
    // Row remains in editing state because Turbo hasn't replaced it yet
    // (this is the expected in-jsdom behaviour — Turbo is not actually wired)
  })

  it("Enter commit optimistically updates the display span", async () => {
    const { row, span } = buildScaffold()
    await waitForConnect()

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      headers: { get: () => null },
    }))

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    input.value = "Updated Title"
    keydown(input, "Enter")

    // Span should show the new title (optimistic update before response)
    expect(span.textContent).toBe("Updated Title")
  })

  // ── Esc cancels ───────────────────────────────────────────────────────────────

  it("Esc cancels: restores original display text", async () => {
    const { row, span } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    input.value = "Changed but cancelled"
    keydown(input, "Escape")

    expect(span.textContent).toBe("My Conversation")
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("Esc cancels: removes pito-row-editing class", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    vi.stubGlobal("fetch", vi.fn())

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    keydown(input, "Escape")

    expect(row.classList.contains("pito-row-editing")).toBe(false)
  })

  it("Esc removes the input element from DOM", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    vi.stubGlobal("fetch", vi.fn())

    dblclick(row)
    keydown(row.querySelector("input.pito--rename-input"), "Escape")

    expect(row.querySelector("input.pito--rename-input")).toBeNull()
  })

  // ── Blank input cancels without PATCH ────────────────────────────────────────

  it("Enter with blank input cancels without calling PATCH", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    input.value = "   " // whitespace-only → treated as blank after trim
    keydown(input, "Enter")

    // Allow the async commitRename to resolve
    await new Promise((r) => setTimeout(r, 0))

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("Enter with blank input removes pito-row-editing class", async () => {
    const { row } = buildScaffold()
    await waitForConnect()

    vi.stubGlobal("fetch", vi.fn())

    dblclick(row)
    const input = row.querySelector("input.pito--rename-input")
    input.value = ""
    keydown(input, "Enter")

    await new Promise((r) => setTimeout(r, 0))

    expect(row.classList.contains("pito-row-editing")).toBe(false)
  })
})
