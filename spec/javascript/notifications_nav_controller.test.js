// spec/javascript/notifications_nav_controller.test.js
//
// Tests for pito--notifications-nav Stimulus controller.
//
// Covers:
//   - Arrow up/down navigation within .pito-notification-row elements
//   - Arrow movement onto an UNREAD row marks it read on arrival (once; never
//     flips read → unread), with a PATCH /notifications/:id { read: true }
//   - Click toggles read ↔ unread (optimistic dot/message class swap) + PATCH
//   - SPACE no longer toggles anything
//   - The list order does NOT change on mark (no client-side re-sort)
//
// jsdom limitations:
//   - scrollIntoView is a no-op stub (no layout engine).
//   - fetch is mocked globally so PATCH assertions don't make real HTTP calls.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import NotificationsNavController from "controllers/pito/notifications_nav_controller"

// ── stubs ─────────────────────────────────────────────────────────────────────
Element.prototype.scrollIntoView = () => {}

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildList() {
  const list = document.createElement("div")
  list.id = "pito-notifications"
  list.setAttribute("data-controller", "pito--notifications-nav")
  document.body.appendChild(list)
  return list
}

function addNotification(list, { id = "1", read = false, createdAt = 0 } = {}) {
  const row = document.createElement("div")
  row.className = "pito-notification-row"
  row.dataset.notificationId = String(id)
  row.dataset.read = String(read)
  row.dataset.createdAt = String(createdAt)

  const dot = document.createElement("span")
  dot.className = read
    ? "pito-notification-dot text-fg-faded"
    : "pito-notification-dot text-cyan"
  dot.textContent = read ? "○" : "●"
  row.appendChild(dot)

  const msg = document.createElement("span")
  msg.className = read
    ? "pito-notification-message text-fg-dim"
    : "pito-notification-message text-fg font-bold"
  msg.textContent = "notification text"
  row.appendChild(msg)

  list.appendChild(row)
  return row
}

function fireKey(k) {
  document.dispatchEvent(
    new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true })
  )
}

function ids(list) {
  return Array.from(list.querySelectorAll(".pito-notification-row")).map(
    (r) => r.dataset.notificationId
  )
}

function tick() {
  return new Promise((r) => setTimeout(r, 0))
}

// ── Suite ─────────────────────────────────────────────────────────────────────

describe("pito--notifications-nav controller", () => {
  let app

  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true })
    app = Application.start()
    app.register("pito--notifications-nav", NotificationsNavController)
  })

  afterEach(async () => {
    // Remove the list while the Stimulus app is still observing so the
    // controller's disconnect() fires (aborting its document-level keydown
    // listener); await a tick to let the MutationObserver process the removal.
    // Only then stop the app. Stopping first leaves the document listener
    // attached (app.stop does not disconnect contexts here), leaking stale
    // controllers that fire phantom PATCHes on later keydowns.
    document.body.innerHTML = ""
    await tick()
    if (app) await app.stop()
    vi.restoreAllMocks()
  })

  // ── Arrow navigation ──────────────────────────────────────────────────────

  it("highlights the first row on connect", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    expect(row1.classList.contains("pito-resume-highlight")).toBe(true)
    expect(row2.classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("ArrowDown moves highlight to next row", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    fireKey("ArrowDown")

    expect(row2.classList.contains("pito-resume-highlight")).toBe(true)
    expect(row1.classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("ArrowUp moves highlight back to first row", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    fireKey("ArrowDown")  // → row2
    fireKey("ArrowUp")    // → row1

    expect(row1.classList.contains("pito-resume-highlight")).toBe(true)
    expect(row2.classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("ArrowDown clamps at the last row", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    fireKey("ArrowDown")  // → row2
    fireKey("ArrowDown")  // stays at row2

    expect(row2.classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("ArrowUp clamps at the first row", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    await tick()

    fireKey("ArrowUp")  // stays at row1

    expect(row1.classList.contains("pito-resume-highlight")).toBe(true)
  })

  // ── SPACE no longer toggles ─────────────────────────────────────────────────

  it("Space does NOT toggle read state", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "5", read: false })
    await tick()

    fireKey(" ")

    expect(row.dataset.read).toBe("false")
    const dot = row.querySelector(".pito-notification-dot")
    expect(dot.textContent).toBe("●")
  })

  it("Space does NOT send a PATCH", async () => {
    const list = buildList()
    addNotification(list, { id: "5", read: false })
    await tick()

    fireKey(" ")

    // Connecting on an unread first row does not auto-mark (only arrows do),
    // so no fetch should have fired from a space press.
    expect(globalThis.fetch).not.toHaveBeenCalled()
  })

  // ── Click toggles read ↔ unread ─────────────────────────────────────────────

  it("click marks an unread notification as read (dot + message classes)", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "5", read: false })
    await tick()

    row.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    const dot = row.querySelector(".pito-notification-dot")
    expect(dot.classList.contains("text-fg-faded")).toBe(true)
    expect(dot.classList.contains("text-cyan")).toBe(false)
    expect(dot.textContent).toBe("○")

    const msg = row.querySelector(".pito-notification-message")
    expect(msg.classList.contains("text-fg-dim")).toBe(true)
    expect(msg.classList.contains("text-fg")).toBe(false)
    expect(msg.classList.contains("font-bold")).toBe(false)

    expect(row.dataset.read).toBe("true")
  })

  it("click marks a read notification as unread (dot + message classes)", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "5", read: true })
    await tick()

    row.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    const dot = row.querySelector(".pito-notification-dot")
    expect(dot.classList.contains("text-cyan")).toBe(true)
    expect(dot.classList.contains("text-fg-faded")).toBe(false)
    expect(dot.textContent).toBe("●")

    const msg = row.querySelector(".pito-notification-message")
    expect(msg.classList.contains("text-fg")).toBe(true)
    expect(msg.classList.contains("font-bold")).toBe(true)
    expect(msg.classList.contains("text-fg-dim")).toBe(false)

    expect(row.dataset.read).toBe("false")
  })

  it("click sends a PATCH /notifications/:id with the new read state", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "7", read: false })
    await tick()

    row.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(globalThis.fetch).toHaveBeenCalledWith(
      "/notifications/7",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ read: true }),
      })
    )
  })

  it("click PATCH includes Content-Type: application/json", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "8", read: false })
    await tick()

    row.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(globalThis.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({ "Content-Type": "application/json" }),
      })
    )
  })

  it("click on a nested element inside a row toggles the row", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "9", read: false })
    await tick()

    const dot = row.querySelector(".pito-notification-dot")
    dot.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(row.dataset.read).toBe("true")
  })

  // ── Arrow-onto-unread marks read on arrival ─────────────────────────────────

  it("ArrowDown onto an unread row marks it read once", async () => {
    const list = buildList()
    addNotification(list, { id: "1", read: true })   // first row already read
    const row2 = addNotification(list, { id: "2", read: false })
    await tick()

    fireKey("ArrowDown")  // highlight lands on unread row2

    expect(row2.dataset.read).toBe("true")
    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
    expect(globalThis.fetch).toHaveBeenCalledWith(
      "/notifications/2",
      expect.objectContaining({ body: JSON.stringify({ read: true }) })
    )
  })

  it("ArrowDown onto an already-read row does NOT flip it to unread and sends no PATCH", async () => {
    const list = buildList()
    addNotification(list, { id: "1", read: true })
    const row2 = addNotification(list, { id: "2", read: true })
    await tick()

    fireKey("ArrowDown")  // lands on already-read row2

    expect(row2.dataset.read).toBe("true")
    expect(globalThis.fetch).not.toHaveBeenCalled()
  })

  it("arrowing back onto a row already marked read does not PATCH again", async () => {
    const list = buildList()
    addNotification(list, { id: "1", read: true })
    addNotification(list, { id: "2", read: false })
    await tick()

    fireKey("ArrowDown")  // marks row2 read (1 PATCH)
    fireKey("ArrowUp")    // back to row1 (already read, no PATCH)
    fireKey("ArrowDown")  // back to row2 (now read, no PATCH)

    expect(globalThis.fetch).toHaveBeenCalledTimes(1)
  })

  // ── No client-side re-sort on mark ──────────────────────────────────────────

  it("clicking to mark read does NOT reorder the list", async () => {
    const list = buildList()
    addNotification(list, { id: "1", read: false, createdAt: 3000 })
    const row2 = addNotification(list, { id: "2", read: false, createdAt: 2000 })
    addNotification(list, { id: "3", read: false, createdAt: 1000 })
    await tick()

    // Mark the middle row read by clicking it.
    row2.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    // Order is unchanged — row2 stays in the middle.
    expect(ids(list)).toEqual(["1", "2", "3"])
    expect(row2.dataset.read).toBe("true")
  })

  it("arrowing onto an unread row does NOT reorder the list", async () => {
    const list = buildList()
    addNotification(list, { id: "1", read: true, createdAt: 3000 })
    addNotification(list, { id: "2", read: false, createdAt: 2000 })
    addNotification(list, { id: "3", read: false, createdAt: 1000 })
    await tick()

    fireKey("ArrowDown")  // marks row id=2 read
    fireKey("ArrowDown")  // marks row id=3 read

    // Order is unchanged despite read-state changes.
    expect(ids(list)).toEqual(["1", "2", "3"])
  })

  // ── Click highlights ────────────────────────────────────────────────────────

  it("click on a row highlights it", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    row2.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(row2.classList.contains("pito-resume-highlight")).toBe(true)
    expect(row1.classList.contains("pito-resume-highlight")).toBe(false)
  })
})
