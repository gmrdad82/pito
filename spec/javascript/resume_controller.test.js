// spec/javascript/resume_controller.test.js
//
// Tests for pito--resume Stimulus controller (resume_controller.js).
//
// Strategy: mount the real controller on a jsdom document with a #pito-sidebar
// scaffold, inject rows after Stimulus connects, then dispatch keyboard events
// and assert highlight movement, Turbo.visit calls, localStorage mutations, and
// the MutationObserver re-pin behaviour.
//
// Timing note: Stimulus connect is asynchronous (one tick). MutationObserver
// callbacks in jsdom are dispatched on a 1 ms delay (not synchronous). Tests
// therefore (a) wait for Stimulus connect before adding rows, and (b) wait for
// MO after DOM mutations using the `waitForMO` helper (several 10 ms sleeps).
//
// jsdom limitations noted inline:
//   - scrollIntoView is a no-op stub (jsdom has no layout engine).
//   - Turbo.renderStreamMessage after fetch() is not tested (requires real Turbo DOM).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ResumeController from "controllers/pito/resume_controller"
import { Turbo } from "@hotwired/turbo-rails"

// ── localStorage polyfill ─────────────────────────────────────────────────────
// jsdom's localStorage is unavailable for opaque origins. Provide a simple
// in-memory stub that matches the Storage interface used by the controller.
const _lsStore = {}
Object.defineProperty(window, "localStorage", {
  writable: true, configurable: true,
  value: {
    getItem:    (k) => Object.prototype.hasOwnProperty.call(_lsStore, k) ? _lsStore[k] : null,
    setItem:    (k, v) => { _lsStore[k] = String(v) },
    removeItem: (k) => { delete _lsStore[k] },
    clear:      () => { Object.keys(_lsStore).forEach((k) => delete _lsStore[k]) },
  }
})

// ── jsdom layout stubs ────────────────────────────────────────────────────────
Element.prototype.scrollIntoView = () => {}

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildSidebar() {
  const sidebar = document.createElement("div")
  sidebar.id = "pito-sidebar"
  sidebar.setAttribute("data-controller", "pito--resume")
  document.body.appendChild(sidebar)
  return sidebar
}

function addRow(sidebar, { uuid = "abc-123", current = false } = {}) {
  const row = document.createElement("div")
  row.className = "pito-conversation-row"
  row.dataset.conversationUuid = uuid
  if (current) row.classList.add("is-current")
  sidebar.appendChild(row)
  return row
}

function fireKey(k, opts = {}) {
  document.dispatchEvent(
    new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true, ...opts })
  )
}

// Wait one tick — enough for Stimulus to connect the controller.
function waitForConnect() {
  return new Promise((r) => setTimeout(r, 10))
}

// Wait for MutationObserver callbacks to flush after a DOM mutation.
// jsdom runs MO callbacks asynchronously; a few 10 ms passes are enough.
function waitForMO() {
  return new Promise((r) => setTimeout(r, 50))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--resume controller", () => {
  let app

  beforeEach(() => {
    localStorage.clear()
    vi.spyOn(Turbo, "visit").mockImplementation(() => {})
    app = Application.start()
    app.register("pito--resume", ResumeController)
  })

  afterEach(async () => {
    vi.restoreAllMocks()
    if (app) await app.stop()
    document.body.innerHTML = ""
    localStorage.clear()
  })

  // ── MutationObserver auto-highlight ───────────────────────────────────────

  it("MutationObserver highlights the first row when rows appear", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(false)
  })

  // ── Arrow key navigation ──────────────────────────────────────────────────

  it("ArrowDown moves highlight to next row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    fireKey("ArrowDown")  // index 0 → 1

    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("ArrowUp moves highlight back to first row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    fireKey("ArrowDown")  // → index 1
    fireKey("ArrowUp")    // → index 0

    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("ArrowDown clamps at the last row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    fireKey("ArrowDown")  // → index 1
    fireKey("ArrowDown")  // stays at index 1 (clamp)

    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowUp clamps at the first row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    fireKey("ArrowUp")  // index 0 — stays at 0 (clamp)

    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowDown does nothing when sidebar is empty", async () => {
    buildSidebar()
    await waitForConnect()
    expect(() => fireKey("ArrowDown")).not.toThrow()
  })

  // ── Enter navigation ──────────────────────────────────────────────────────

  it("Enter on a non-current row calls Turbo.visit with /chat/<uuid>", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "conv-42" })
    await waitForMO()

    fireKey("Enter")

    expect(Turbo.visit).toHaveBeenCalledWith("/chat/conv-42")
  })

  it("Enter on an is-current row clears the sidebar instead of visiting", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "conv-42", current: true })
    await waitForMO()

    fireKey("Enter")

    expect(Turbo.visit).not.toHaveBeenCalled()
    expect(sidebar.innerHTML.trim()).toBe("")
  })

  it("Enter clears the sidebar content after navigating", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "conv-42" })
    await waitForMO()

    fireKey("Enter")

    expect(sidebar.innerHTML.trim()).toBe("")
  })

  // ── Escape ────────────────────────────────────────────────────────────────

  it("Escape clears the sidebar when it has content", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    fireKey("Escape")
    await waitForMO()

    expect(sidebar.innerHTML.trim()).toBe("")
  })

  it("Escape removes localStorage[pito:sidebar]", async () => {
    localStorage.setItem("pito:sidebar", "conversations")
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    fireKey("Escape")

    expect(localStorage.getItem("pito:sidebar")).toBeNull()
  })

  it("Escape when sidebar is empty allows the keydown event to propagate", async () => {
    // The capture-phase listener returns early when the sidebar is empty, so
    // a bubbling listener registered after it should still fire.
    const sidebar = buildSidebar()
    await waitForConnect()
    // sidebar is empty — no rows

    let propagated = false
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") propagated = true
    }, { capture: false, once: true })

    fireKey("Escape")

    expect(propagated).toBe(true)
  })

  // ── Backtick dispatches pito:rename:start ─────────────────────────────────

  it("Backtick on the highlighted row dispatches pito:rename:start on that row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    let renameEvent = null
    row.addEventListener("pito:rename:start", (e) => { renameEvent = e })

    fireKey("`")

    expect(renameEvent).not.toBeNull()
  })

  // ── MutationObserver re-pin ───────────────────────────────────────────────

  it("MutationObserver re-pins highlight after a row is replaced", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()  // MO fires, index=0

    fireKey("ArrowDown")  // move to index 1

    // Simulate a Turbo row replace on index 1.
    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    const newRow = document.createElement("div")
    newRow.className = "pito-conversation-row"
    newRow.dataset.conversationUuid = "u2-renamed"
    sidebar.replaceChild(newRow, rows[1])

    await waitForMO()  // MO fires, re-pins to same index

    const allRows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(allRows[1].classList.contains("pito-resume-highlight")).toBe(true)
  })

  // ── d-key: arm then delete ────────────────────────────────────────────────

  it("pressing d arms the highlighted row with a confirm prompt", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "del-1" })
    await waitForMO()

    fireKey("d")

    // Row should now show the confirm prompt text (not its original empty content).
    expect(row.innerHTML).toContain("press d again to delete")
  })

  it("pressing d twice deletes the conversation via fetch DELETE", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "del-2" })
    await waitForMO()

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })

    fireKey("d")  // arm
    fireKey("d")  // confirm delete

    expect(fetchSpy).toHaveBeenCalledWith(
      "/chat/del-2",
      expect.objectContaining({ method: "DELETE" })
    )
  })

  it("pressing d a second time removes the row on success", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "del-3" })
    await waitForMO()

    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })

    fireKey("d")
    fireKey("d")

    // Give the async fetch promise a tick to resolve.
    await new Promise((r) => setTimeout(r, 20))

    expect(sidebar.contains(row)).toBe(false)
  })

  it("pressing ArrowDown disarms the armed row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    fireKey("d")
    // Row should be armed.
    expect(row.innerHTML).toContain("press d again to delete")

    fireKey("ArrowDown")
    // Row should be disarmed (original HTML restored — was empty div).
    expect(row.innerHTML).not.toContain("press d again to delete")
  })

  it("pressing Escape disarms the row without clearing the sidebar", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    fireKey("d")
    expect(row.innerHTML).toContain("press d again to delete")

    fireKey("Escape")
    // Row should be disarmed.
    expect(row.innerHTML).not.toContain("press d again to delete")
    // Sidebar should still have the row (not cleared).
    expect(sidebar.contains(row)).toBe(true)
  })

  // ── localStorage persist on content-change ────────────────────────────────

  it("persists 'conversations' to localStorage when conversation rows appear", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    expect(localStorage.getItem("pito:sidebar")).toBe("conversations")
  })

  it("persists 'notifications' to localStorage when notification rows appear", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    const notifRow = document.createElement("div")
    notifRow.className = "pito-notification-row"
    sidebar.appendChild(notifRow)
    await waitForMO()

    expect(localStorage.getItem("pito:sidebar")).toBe("notifications")
  })

  // ── #restore() fetch on connect ───────────────────────────────────────────

  it("fetches /resume on connect when localStorage has 'conversations'", async () => {
    // NOTE: Turbo.renderStreamMessage is not tested here — jsdom cannot process
    // a Turbo Stream HTML response without a full Turbo runtime. We verify only
    // that fetch is called with the correct URL and Accept header.
    localStorage.setItem("pito:sidebar", "conversations")

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      text: async () => "",
    })

    buildSidebar()  // empty sidebar triggers #restore() on connect
    await waitForConnect()

    expect(fetchSpy).toHaveBeenCalledWith(
      expect.stringMatching(/\/resume/),
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: "text/vnd.turbo-stream.html" }),
      })
    )
  })

  it("fetches /notifications on connect when localStorage has 'notifications'", async () => {
    localStorage.setItem("pito:sidebar", "notifications")

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      text: async () => "",
    })

    buildSidebar()
    await waitForConnect()

    expect(fetchSpy).toHaveBeenCalledWith(
      "/notifications",
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: "text/vnd.turbo-stream.html" }),
      })
    )
  })

  it("does not fetch on connect when sidebar already has content", async () => {
    localStorage.setItem("pito:sidebar", "conversations")

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      text: async () => "",
    })

    const sidebar = buildSidebar()
    sidebar.innerHTML = "<div>already loaded</div>"
    await waitForConnect()

    expect(fetchSpy).not.toHaveBeenCalled()
  })
})
