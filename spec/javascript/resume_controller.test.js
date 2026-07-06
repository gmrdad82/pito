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

// ── Touch helpers (Z22 swipe-to-delete) ───────────────────────────────────────
// jsdom has no TouchEvent constructor; synthesize a bubbling, cancelable Event
// and attach touches/changedTouches with the client coords the controller reads.
function fireTouch(el, type, x, y) {
  const ev = new Event(type, { bubbles: true, cancelable: true })
  const points = [ { clientX: x, clientY: y } ]
  ev.touches = points
  ev.changedTouches = points
  el.dispatchEvent(ev)
  return ev
}

// Make the swipe gesture think we're on a narrow touch viewport.
function enableSwipe() {
  window.matchMedia = (q) => ({
    matches: /max-width: 767px/.test(q) && /pointer: coarse/.test(q),
    media: q, addEventListener() {}, removeEventListener() {},
    addListener() {}, removeListener() {},
  })
}

// A conversation row matching conversations/_row.html.erb structure: a row shell
// with a sliding .pito-conversation-row__content and a [data-conversation-delete]
// button revealed by the swipe.
function addSwipeRow(sidebar, { uuid = "abc-123" } = {}) {
  const row = document.createElement("div")
  row.className = "pito-conversation-row"
  row.dataset.conversationUuid = uuid

  const del = document.createElement("button")
  del.setAttribute("data-conversation-delete", "")
  del.textContent = "delete"
  row.appendChild(del)

  const content = document.createElement("div")
  content.className = "pito-conversation-row__content"
  row.appendChild(content)

  sidebar.appendChild(row)
  return row
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
    // Reset the swipe gesture media-query stub between tests.
    window.matchMedia = undefined
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

  // ── Click selection (= arrow-to-it + Enter) ───────────────────────────────

  it("clicking a non-current row calls Turbo.visit with /chat/<uuid>", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    const row2 = addRow(sidebar, { uuid: "click-99" })
    await waitForMO()

    row2.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(Turbo.visit).toHaveBeenCalledWith("/chat/click-99")
    expect(sidebar.innerHTML.trim()).toBe("")
  })

  it("clicking a row pins the highlight to it before selecting", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    const row2 = addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    // Highlight starts on row 0. Clicking row 1 pins the highlight to it (paint
    // runs before #select clears the sidebar; the detached node keeps the class).
    row2.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(row2.classList.contains("pito-resume-highlight")).toBe(true)
    expect(Turbo.visit).toHaveBeenCalledWith("/chat/u2")
  })

  it("clicking an is-current row clears the sidebar instead of visiting", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "cur-1", current: true })
    await waitForMO()

    row.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(Turbo.visit).not.toHaveBeenCalled()
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

  // ── n dispatches pito:rename:start ───────────────────────────────────────

  it("n on the highlighted row dispatches pito:rename:start on that row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    let renameEvent = null
    row.addEventListener("pito:rename:start", (e) => { renameEvent = e })

    fireKey("n")

    expect(renameEvent).not.toBeNull()
  })

  it("backtick no longer dispatches pito:rename:start on the highlighted row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    let renameEvent = null
    row.addEventListener("pito:rename:start", (e) => { renameEvent = e })

    fireKey("`")

    expect(renameEvent).toBeNull()
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
    expect(row.innerHTML).toContain("Press d again to delete")
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

  it("pressing d a second time fires the async DELETE and leaves the row for the server to remove", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "del-3" })
    await waitForMO()

    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })

    fireKey("d")
    fireKey("d")

    // Give the async fetch promise a tick to resolve.
    await new Promise((r) => setTimeout(r, 20))

    // Async delete (Phase J): the client sends DELETE /chat/<uuid> and does NOT
    // remove the row itself — the server marks it deleting and broadcasts
    // row → shimmering-dots → removal over pito:global. So the row stays put here.
    expect(fetchMock).toHaveBeenCalledWith(
      "/chat/del-3",
      expect.objectContaining({ method: "DELETE" })
    )
    expect(sidebar.contains(row)).toBe(true)
  })

  it("pressing ArrowDown disarms the armed row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    fireKey("d")
    // Row should be armed.
    expect(row.innerHTML).toContain("Press d again to delete")

    fireKey("ArrowDown")
    // Row should be disarmed (original HTML restored — was empty div).
    expect(row.innerHTML).not.toContain("Press d again to delete")
  })

  it("pressing Escape disarms the row without clearing the sidebar", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    fireKey("d")
    expect(row.innerHTML).toContain("Press d again to delete")

    fireKey("Escape")
    // Row should be disarmed.
    expect(row.innerHTML).not.toContain("Press d again to delete")
    // Sidebar should still have the row (not cleared).
    expect(sidebar.contains(row)).toBe(true)
  })

  it("armed state auto-disarms after 500ms without a second d", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    // Switch to fake timers AFTER async setup so waitForConnect/waitForMO run normally.
    vi.useFakeTimers()
    try {
      fireKey("d")
      expect(row.innerHTML).toContain("Press d again to delete")

      vi.advanceTimersByTime(600)
      // Timer expired — row should be disarmed and original HTML restored.
      expect(row.innerHTML).not.toContain("Press d again to delete")
    } finally {
      vi.useRealTimers()
    }
  })

  it("dd within 500ms deletes (second d before timeout fires)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "fast-dd" })
    await waitForMO()

    vi.useFakeTimers()
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })
    try {
      fireKey("d")   // arm
      vi.advanceTimersByTime(200)  // well within the 500ms window
      fireKey("d")   // second d — triggers delete

      expect(fetchSpy).toHaveBeenCalledWith(
        "/chat/fast-dd",
        expect.objectContaining({ method: "DELETE" })
      )
    } finally {
      vi.useRealTimers()
    }
  })

  it("single d followed by timeout does NOT delete", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "lone-d" })
    await waitForMO()

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })
    vi.useFakeTimers()
    try {
      fireKey("d")                    // arm
      vi.advanceTimersByTime(600)     // past the 500ms window — auto-disarm fires
      // No second d — fetch should not have been called
      expect(fetchSpy).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
    }
  })

  it("d while a SIDEBAR input (inline rename) has focus does not arm the row", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    // The inline rename field lives INSIDE the sidebar — d must type into it,
    // not arm the row.
    const input = document.createElement("input")
    row.appendChild(input)
    input.focus()

    fireKey("d")

    expect(row.innerHTML).toContain("<input")
    expect(row.innerHTML).not.toContain("Press d again to delete")
  })

  it("d still arms the row when the chatbox (outside the sidebar) has focus, and blurs it", async () => {
    // J22: a focused chatbox must NOT swallow delete. d should blur the chatbox
    // and arm the highlighted row so it never gets typed into the chatbox.
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addRow(sidebar, { uuid: "u1" })
    await waitForMO()

    const chatbox = document.createElement("textarea")
    chatbox.setAttribute("data-pito--chat-form-target", "inputField")
    document.body.appendChild(chatbox)
    chatbox.focus()
    expect(document.activeElement).toBe(chatbox)

    fireKey("d")

    expect(row.innerHTML).toContain("Press d again to delete")
    expect(document.activeElement).not.toBe(chatbox)

    chatbox.remove()
  })

  it("dd deletes even with the chatbox focused (delete is never swallowed)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "del-focus" })
    await waitForMO()

    const chatbox = document.createElement("textarea")
    chatbox.setAttribute("data-pito--chat-form-target", "inputField")
    document.body.appendChild(chatbox)
    chatbox.focus()

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })

    fireKey("d")  // arm (blurs chatbox)
    fireKey("d")  // confirm delete

    expect(fetchSpy).toHaveBeenCalledWith(
      "/chat/del-focus",
      expect.objectContaining({ method: "DELETE" })
    )

    chatbox.remove()
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

  it("does not restore on the start screen (home-transition present), even with localStorage set", async () => {
    // The start screen + dynamic 404 never show a sidebar; #restore must bail
    // so deleting the last conversation doesn't re-open it.
    localStorage.setItem("pito:sidebar", "conversations")
    const home = document.createElement("div")
    home.setAttribute("data-controller", "pito--home-transition")
    document.body.appendChild(home)

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, text: async () => "" })

    buildSidebar()
    await waitForConnect()

    expect(fetchSpy).not.toHaveBeenCalled()
  })

  // ── Blur-on-open ──────────────────────────────────────────────────────────

  it("blurs the chatbox when the sidebar gains content (an <aside>)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    const chatbox = document.createElement("textarea")
    chatbox.setAttribute("data-pito--chat-form-target", "inputField")
    document.body.appendChild(chatbox)
    chatbox.focus()
    expect(document.activeElement).toBe(chatbox)

    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await waitForMO()

    expect(document.activeElement).not.toBe(chatbox)

    chatbox.remove()
  })

  it("dispatches pito:comet-clear when the sidebar opens (J23 — comet must not hang)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    let cometCleared = false
    document.addEventListener("pito:comet-clear", () => { cometCleared = true }, { once: true })

    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await waitForMO()

    expect(cometCleared).toBe(true)
  })

  it("does not re-dispatch pito:comet-clear on a later in-place mutation (only on open)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await waitForMO()  // open transition — comet-clear fires here

    let count = 0
    document.addEventListener("pito:comet-clear", () => { count++ })

    // An in-place mutation while the panel stays open (e.g. a rename row replace).
    aside.appendChild(document.createElement("div"))
    await waitForMO()

    expect(count).toBe(0)
  })

  it("keys still navigate normally when focus is not in a text input (guard does not fire)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()
    addRow(sidebar, { uuid: "u1" })
    addRow(sidebar, { uuid: "u2" })
    await waitForMO()

    // Add <aside> — but no textarea is focused, so guard must not trigger
    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await waitForMO()

    fireKey("ArrowDown")  // should move highlight from row0 to row1

    const rows = sidebar.querySelectorAll(".pito-conversation-row")
    expect(rows[1].classList.contains("pito-resume-highlight")).toBe(true)
    expect(rows[0].classList.contains("pito-resume-highlight")).toBe(false)
  })

  // ── Z24: overlay resets scroll to top on open ─────────────────────────────

  it("resets the scroll body to the top when the panel opens", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    const aside = document.createElement("aside")
    const scroller = document.createElement("div")
    scroller.className = "pito-scroll-fade-slim"
    // Back scrollTop with a real property (jsdom has no layout engine).
    let st = 0
    Object.defineProperty(scroller, "scrollTop", {
      configurable: true, get: () => st, set: (v) => { st = v },
    })
    scroller.scrollTop = 240          // pretend it opened scrolled down
    aside.appendChild(scroller)
    sidebar.appendChild(aside)
    await waitForMO()

    expect(scroller.scrollTop).toBe(0)
  })

  it("does not reset scroll on a later in-place mutation (e.g. rename)", async () => {
    const sidebar = buildSidebar()
    await waitForConnect()

    const aside = document.createElement("aside")
    const scroller = document.createElement("div")
    scroller.className = "pito-scroll-fade-slim"
    let st = 0
    Object.defineProperty(scroller, "scrollTop", {
      configurable: true, get: () => st, set: (v) => { st = v },
    })
    aside.appendChild(scroller)
    sidebar.appendChild(aside)
    await waitForMO()  // open transition — reset fires (st already 0)

    // User scrolls down, then an in-place row mutation occurs (panel stays open).
    scroller.scrollTop = 180
    scroller.appendChild(document.createElement("div"))
    await waitForMO()

    expect(scroller.scrollTop).toBe(180)  // preserved — not yanked to top
  })

  // ── Z22: mobile swipe-to-delete ───────────────────────────────────────────

  it("a left swipe past the threshold snaps the row open (reveals Delete)", async () => {
    enableSwipe()
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addSwipeRow(sidebar, { uuid: "sw-1" })
    await waitForMO()

    fireTouch(row, "touchstart", 200, 50)
    fireTouch(row, "touchmove", 130, 52)  // dx = -70 (past 48 threshold)
    fireTouch(row, "touchend", 130, 52)

    expect(row.classList.contains("pito-row-swipe-open")).toBe(true)
  })

  it("tapping the revealed Delete button deletes via fetch DELETE", async () => {
    enableSwipe()
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addSwipeRow(sidebar, { uuid: "sw-del" })
    await waitForMO()

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })

    fireTouch(row, "touchstart", 200, 50)
    fireTouch(row, "touchmove", 120, 50)
    fireTouch(row, "touchend", 120, 50)

    row.querySelector("[data-conversation-delete]")
      .dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(fetchSpy).toHaveBeenCalledWith(
      "/chat/sw-del",
      expect.objectContaining({ method: "DELETE" })
    )
    // The swipe must NOT have navigated.
    expect(Turbo.visit).not.toHaveBeenCalled()
  })

  it("a short swipe does NOT open the row or delete", async () => {
    enableSwipe()
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addSwipeRow(sidebar, { uuid: "sw-short" })
    await waitForMO()

    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })

    fireTouch(row, "touchstart", 200, 50)
    fireTouch(row, "touchmove", 185, 50)  // dx = -15 (below 48 threshold)
    fireTouch(row, "touchend", 185, 50)

    expect(row.classList.contains("pito-row-swipe-open")).toBe(false)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("a mostly-vertical drag does NOT open the row (list scroll preserved)", async () => {
    enableSwipe()
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addSwipeRow(sidebar, { uuid: "sw-vert" })
    await waitForMO()

    fireTouch(row, "touchstart", 200, 50)
    const move = fireTouch(row, "touchmove", 196, 130)  // dy=80 ≫ dx=-4 → vertical
    fireTouch(row, "touchend", 196, 130)

    expect(row.classList.contains("pito-row-swipe-open")).toBe(false)
    // Vertical drags must not be hijacked — the controller leaves scroll alone.
    expect(move.defaultPrevented).toBe(false)
  })

  it("opening one row closes a previously open row", async () => {
    enableSwipe()
    const sidebar = buildSidebar()
    await waitForConnect()
    const row1 = addSwipeRow(sidebar, { uuid: "sw-a" })
    const row2 = addSwipeRow(sidebar, { uuid: "sw-b" })
    await waitForMO()

    // Open row1.
    fireTouch(row1, "touchstart", 200, 40)
    fireTouch(row1, "touchmove", 120, 40)
    fireTouch(row1, "touchend", 120, 40)
    expect(row1.classList.contains("pito-row-swipe-open")).toBe(true)

    // Open row2 — row1 must close.
    fireTouch(row2, "touchstart", 200, 80)
    fireTouch(row2, "touchmove", 120, 80)
    fireTouch(row2, "touchend", 120, 80)

    expect(row2.classList.contains("pito-row-swipe-open")).toBe(true)
    expect(row1.classList.contains("pito-row-swipe-open")).toBe(false)
  })

  it("swipe gesture is inert on desktop (no matchMedia coarse match)", async () => {
    // Do NOT enableSwipe() — #swipeEnabled() returns false.
    const sidebar = buildSidebar()
    await waitForConnect()
    const row = addSwipeRow(sidebar, { uuid: "sw-desktop" })
    await waitForMO()

    fireTouch(row, "touchstart", 200, 50)
    fireTouch(row, "touchmove", 110, 50)
    fireTouch(row, "touchend", 110, 50)

    expect(row.classList.contains("pito-row-swipe-open")).toBe(false)
  })

  // ── Desktop overlay backdrop (SB) ─────────────────────────────────────────

  it("clicking #pito-sidebar-backdrop dismisses the sidebar", async () => {
    const sidebar = buildSidebar()
    const backdrop = document.createElement("div")
    backdrop.id = "pito-sidebar-backdrop"
    document.body.appendChild(backdrop)
    await waitForConnect()

    // Open the sidebar by injecting an <aside>.
    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await waitForMO()

    // Sidebar has content before the click.
    expect(sidebar.innerHTML.trim()).not.toBe("")

    backdrop.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    // Sidebar should now be cleared (dismissed).
    expect(sidebar.innerHTML.trim()).toBe("")
  })

  it("connects gracefully when #pito-sidebar-backdrop is absent from the DOM", async () => {
    // No backdrop element in DOM — controller must not throw, and other
    // dismiss paths (pito:resume:dismiss) must still work.
    const sidebar = buildSidebar()
    await waitForConnect()

    const aside = document.createElement("aside")
    sidebar.appendChild(aside)
    await waitForMO()

    expect(sidebar.innerHTML.trim()).not.toBe("")

    // Dismiss via the window event (the backdrop-absent path).
    window.dispatchEvent(new CustomEvent("pito:resume:dismiss"))

    expect(sidebar.innerHTML.trim()).toBe("")
  })
})
