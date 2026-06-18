// spec/javascript/notifications_nav_controller.test.js
//
// Tests for pito--notifications-nav Stimulus controller.
//
// Covers:
//   - Arrow up/down navigation within .pito-notification-row elements
//   - Space toggles read/unread: optimistic dot class + text class swap, plus
//     a PATCH /notifications/:id { read: <bool> } fetch call
//   - click selects a row (moves highlight)
//
// jsdom limitations:
//   - scrollIntoView is a no-op stub (no layout engine).
//   - fetch is mocked globally so PATCH assertions don't make real HTTP calls.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import NotificationsNavController from "controllers/pito/notifications_nav_controller"

// ── stubs ─────────────────────────────────────────────────────────────────────
Element.prototype.scrollIntoView = () => {}

// Build a #pito-sidebar with an <aside> child so the guard condition
// (document.querySelector("#pito-sidebar aside")) evaluates to truthy.
function buildActiveSidebar() {
  const sidebar = document.createElement("div")
  sidebar.id = "pito-sidebar"
  const aside = document.createElement("aside")
  sidebar.appendChild(aside)
  document.body.appendChild(sidebar)
  return sidebar
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildList() {
  const list = document.createElement("div")
  list.id = "pito-notifications"
  list.setAttribute("data-controller", "pito--notifications-nav")
  document.body.appendChild(list)
  return list
}

function addNotification(list, { id = "1", read = false } = {}) {
  const row = document.createElement("div")
  row.className = "pito-notification-row"
  row.dataset.notificationId = String(id)
  row.dataset.read = String(read)

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
    vi.restoreAllMocks()
    if (app) await app.stop()
    document.body.innerHTML = ""
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

  // ── Space toggle ──────────────────────────────────────────────────────────

  it("Space optimistically marks an unread notification as read (dot class)", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "5", read: false })
    await tick()

    fireKey(" ")

    const dot = row.querySelector(".pito-notification-dot")
    expect(dot.classList.contains("text-fg-faded")).toBe(true)
    expect(dot.classList.contains("text-cyan")).toBe(false)
    expect(dot.textContent).toBe("○")
  })

  it("Space optimistically marks an unread notification as read (message class)", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "5", read: false })
    await tick()

    fireKey(" ")

    const msg = row.querySelector(".pito-notification-message")
    expect(msg.classList.contains("text-fg-dim")).toBe(true)
    expect(msg.classList.contains("text-fg")).toBe(false)
    expect(msg.classList.contains("font-bold")).toBe(false)
  })

  it("Space optimistically marks a read notification as unread (dot class)", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "5", read: true })
    await tick()

    fireKey(" ")

    const dot = row.querySelector(".pito-notification-dot")
    expect(dot.classList.contains("text-cyan")).toBe(true)
    expect(dot.classList.contains("text-fg-faded")).toBe(false)
    expect(dot.textContent).toBe("●")
  })

  it("Space sends a PATCH /notifications/:id with the new read state", async () => {
    const list = buildList()
    addNotification(list, { id: "7", read: false })
    await tick()

    fireKey(" ")

    expect(globalThis.fetch).toHaveBeenCalledWith(
      "/notifications/7",
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({ read: true }),
      })
    )
  })

  it("Space PATCH includes Content-Type: application/json", async () => {
    const list = buildList()
    addNotification(list, { id: "8", read: false })
    await tick()

    fireKey(" ")

    expect(globalThis.fetch).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        headers: expect.objectContaining({ "Content-Type": "application/json" }),
      })
    )
  })

  it("Space flips data-read attribute on the row", async () => {
    const list = buildList()
    const row = addNotification(list, { id: "9", read: false })
    await tick()

    fireKey(" ")

    expect(row.dataset.read).toBe("true")
  })

  // ── click selects row ──────────────────────────────────────────────────────

  it("click on a row highlights it", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    row2.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(row2.classList.contains("pito-resume-highlight")).toBe(true)
    expect(row1.classList.contains("pito-resume-highlight")).toBe(false)
  })

  it("click on a nested element inside a row highlights the row", async () => {
    const list = buildList()
    const row1 = addNotification(list, { id: "1" })
    const row2 = addNotification(list, { id: "2" })
    await tick()

    // Click on the dot inside row2
    const dot = row2.querySelector(".pito-notification-dot")
    dot.dispatchEvent(new MouseEvent("click", { bubbles: true }))

    expect(row2.classList.contains("pito-resume-highlight")).toBe(true)
  })

  it("Space still toggles the notification when focus is not in a text input", async () => {
    // No textarea focused and no sidebar <aside> — guard does not fire
    const list = buildList()
    const row = addNotification(list, { id: "5", read: false })
    await tick()

    fireKey(" ")

    expect(row.dataset.read).toBe("true")
  })
})
