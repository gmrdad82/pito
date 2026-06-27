// spec/javascript/list_pager_controller.test.js
//
// Tests for pito/list_pager_controller.js — the generic keyset/infinite-scroll
// pager. It triggers on (a) the sentinel intersecting the scroll root, or
// (b) a `pito:list-pager:more` event (dispatched by a list's keyboard nav when
// ↓ is pressed at the last row). It fetches the sentinel's opaque
// `data-pager-next-url` as a Turbo Stream; with no URL (end of list) it no-ops.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import ListPagerController from "controllers/pito/list_pager_controller"

const tick = () => new Promise((r) => setTimeout(r, 10))

// jsdom has no IntersectionObserver — capture instances so tests can fire them.
let observers
class FakeIO {
  constructor(cb) { this.cb = cb; this.els = []; observers.push(this) }
  observe(el) { this.els.push(el) }
  disconnect() { this.els = [] }
  trigger(isIntersecting = true) {
    this.cb(this.els.map((target) => ({ isIntersecting, target })))
  }
}

function buildDOM({ nextUrl } = {}) {
  const wrapper = document.createElement("div")
  wrapper.className = "overflow-y-auto" // doubles as its own scroll root
  wrapper.setAttribute("data-controller", "pito--list-pager")

  const list = document.createElement("div")
  list.setAttribute("data-pito--list-pager-target", "list")
  wrapper.appendChild(list)

  const sentinel = document.createElement("div")
  sentinel.id = "pito-list-pager-sentinel"
  sentinel.setAttribute("data-pito--list-pager-target", "sentinel")
  if (nextUrl) sentinel.setAttribute("data-pager-next-url", nextUrl)

  const loader = document.createElement("p")
  loader.className = "hidden"
  loader.setAttribute("data-pito--list-pager-target", "loader")
  sentinel.appendChild(loader)
  wrapper.appendChild(sentinel)

  document.body.appendChild(wrapper)
  return { wrapper, list, sentinel, loader }
}

describe("ListPagerController", () => {
  let app

  beforeEach(() => {
    observers = []
    vi.stubGlobal("IntersectionObserver", FakeIO)
    window.Turbo = { renderStreamMessage: vi.fn() }
    app = Application.start()
    app.register("pito--list-pager", ListPagerController)
  })

  afterEach(async () => {
    await app.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
  })

  it("fetches the next-page URL and reveals the loader on intersection", async () => {
    const { loader } = buildDOM({ nextUrl: "/notifications?after=abc" })
    await tick()
    const fetchMock = vi.fn().mockResolvedValue({
      text: () => Promise.resolve("<turbo-stream></turbo-stream>"),
    })
    vi.stubGlobal("fetch", fetchMock)

    observers[0].trigger(true)

    expect(loader.classList.contains("hidden")).toBe(false)
    expect(fetchMock).toHaveBeenCalledWith(
      "/notifications?after=abc",
      expect.objectContaining({
        headers: expect.objectContaining({ Accept: expect.stringContaining("turbo-stream") }),
      })
    )
  })

  it("fetches on a pito:list-pager:more event (↓ at last row)", async () => {
    const { wrapper } = buildDOM({ nextUrl: "/notifications?after=xyz" })
    await tick()
    const fetchMock = vi.fn().mockResolvedValue({ text: () => Promise.resolve("") })
    vi.stubGlobal("fetch", fetchMock)

    wrapper.dispatchEvent(new CustomEvent("pito:list-pager:more"))

    expect(fetchMock).toHaveBeenCalledWith("/notifications?after=xyz", expect.anything())
  })

  it("does NOT fetch when the sentinel has no next URL (end of list)", async () => {
    buildDOM({}) // end state
    await tick()
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)

    observers[0].trigger(true)

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("does not fire a second fetch while one is already in flight", async () => {
    buildDOM({ nextUrl: "/notifications?after=abc" })
    await tick()
    const fetchMock = vi.fn().mockReturnValue(new Promise(() => {})) // never resolves
    vi.stubGlobal("fetch", fetchMock)

    observers[0].trigger(true)
    observers[0].trigger(true)

    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
})
