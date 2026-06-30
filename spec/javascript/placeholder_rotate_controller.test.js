// spec/javascript/placeholder_rotate_controller.test.js
//
// Tests for pito/placeholder_rotate_controller.js — cycles a field's native
// `placeholder` through a JSON list of hints every `interval` ms. This replaces
// the old comet "showcase ghost"; the hints now ride the native placeholder.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import PlaceholderRotateController from "controllers/pito/placeholder_rotate_controller"

function buildDOM(hints = ["list games", "list vids"], original = "original hint") {
  document.body.innerHTML = `
    <div id="pito-chatbox"
         data-controller="pito--placeholder-rotate"
         data-pito--placeholder-rotate-interval-value="1000">
      <script type="application/json" id="pito-showcase-data"
              data-pito--placeholder-rotate-target="data">${JSON.stringify(hints)}</script>
      <textarea data-pito--placeholder-rotate-target="field" placeholder="${original}"></textarea>
    </div>
  `
  return {
    chatbox: document.getElementById("pito-chatbox"),
    field: document.querySelector("textarea"),
  }
}

describe("PlaceholderRotateController", () => {
  let app

  beforeEach(async () => {
    vi.useFakeTimers()
    app = Application.start()
    app.register("pito--placeholder-rotate", PlaceholderRotateController)
    await Promise.resolve()
  })

  afterEach(() => {
    app.stop()
    document.body.innerHTML = ""
    vi.useRealTimers()
  })

  it("shows the server-rendered placeholder first, then cycles the hints", async () => {
    const { field } = buildDOM(["list games", "list vids"])
    await Promise.resolve()

    expect(field.getAttribute("placeholder")).toBe("original hint")

    vi.advanceTimersByTime(1000)
    expect(field.getAttribute("placeholder")).toBe("list games")

    vi.advanceTimersByTime(1000)
    expect(field.getAttribute("placeholder")).toBe("list vids")

    // wraps back to the first hint
    vi.advanceTimersByTime(1000)
    expect(field.getAttribute("placeholder")).toBe("list games")
  })

  it("keeps the original placeholder when there are no hints", async () => {
    const { field } = buildDOM([])
    await Promise.resolve()

    vi.advanceTimersByTime(5000)
    expect(field.getAttribute("placeholder")).toBe("original hint")
  })

  it("restores the original placeholder on disconnect", async () => {
    const { chatbox, field } = buildDOM(["list games"])
    await Promise.resolve()

    vi.advanceTimersByTime(1000)
    expect(field.getAttribute("placeholder")).toBe("list games")

    chatbox.remove() // triggers disconnect
    await Promise.resolve()
    expect(field.getAttribute("placeholder")).toBe("original hint")
  })

  it("reloads hints and restarts when #pito-showcase-data is replaced", async () => {
    const { chatbox, field } = buildDOM(["list games"])
    await Promise.resolve()

    // Simulate a Turbo Stream replace of the data script (remove old, add new).
    document.getElementById("pito-showcase-data").remove()
    const fresh = document.createElement("script")
    fresh.type = "application/json"
    fresh.id = "pito-showcase-data"
    fresh.setAttribute("data-pito--placeholder-rotate-target", "data")
    fresh.textContent = JSON.stringify(["sync channels"])
    chatbox.appendChild(fresh)
    await Promise.resolve()
    await Promise.resolve()

    vi.advanceTimersByTime(1000)
    expect(field.getAttribute("placeholder")).toBe("sync channels")
  })
})
