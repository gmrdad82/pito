// spec/javascript/version_watch_controller.test.js
//
// Vitest (jsdom) suite for pito--version-watch (G80): each heartbeat replace
// of #pito-server-version mounts this controller; a version differing from
// the page's pito-version meta clones the refresh nudge into the scrollback.
// Consuming the template is the once-per-page guard shared with cable-health.

import { describe, it, expect, afterEach, beforeEach, vi } from "vitest"
import { Application } from "@hotwired/stimulus"
import VersionWatchController from "controllers/pito/version_watch_controller"

// jsdom does not implement scrollIntoView — the nudge clone calls it, and the
// resulting jsdomError surfaces as an unhandled rejection that fails CI.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn()
})

function scaffold({ pageVersion, serverVersion }) {
  if (pageVersion) {
    const meta = document.createElement("meta")
    meta.name = "pito-version"
    meta.content = pageVersion
    document.head.appendChild(meta)
  }

  const scrollback = document.createElement("div")
  scrollback.id = "pito-scrollback"
  document.body.appendChild(scrollback)

  const template = document.createElement("template")
  template.id = "pito-refresh-nudge"
  template.innerHTML = '<div class="pito-turn">nudge</div>'
  document.body.appendChild(template)

  const node = document.createElement("div")
  node.id = "pito-server-version"
  node.setAttribute("data-controller", "pito--version-watch")
  node.setAttribute("data-pito--version-watch-version-value", serverVersion)
  document.body.appendChild(node)

  return { scrollback }
}

describe("pito--version-watch controller", () => {
  let app

  async function start() {
    app = Application.start()
    app.register("pito--version-watch", VersionWatchController)
    await Promise.resolve()
  }

  afterEach(async () => {
    document.body.innerHTML = ""
    document.head.querySelector('meta[name="pito-version"]')?.remove()
    await Promise.resolve() // let Stimulus's MutationObserver fire disconnect()
    app.stop()
  })

  it("raises the nudge when the heartbeat's version differs from the page's", async () => {
    const { scrollback } = scaffold({ pageVersion: "1.0.1", serverVersion: "1.1.0" })
    await start()

    expect(scrollback.querySelector(".pito-turn")).not.toBeNull()
    expect(document.getElementById("pito-refresh-nudge")).toBeNull() // template consumed
  })

  it("stays quiet when the versions match", async () => {
    const { scrollback } = scaffold({ pageVersion: "1.1.0", serverVersion: "1.1.0" })
    await start()

    expect(scrollback.querySelector(".pito-turn")).toBeNull()
    expect(document.getElementById("pito-refresh-nudge")).not.toBeNull()
  })

  it("stays quiet without a page version meta (anonymous/edge pages)", async () => {
    const { scrollback } = scaffold({ pageVersion: null, serverVersion: "1.1.0" })
    await start()

    expect(scrollback.querySelector(".pito-turn")).toBeNull()
  })

  it("nudges at most once per page life — the consumed template guards repeat heartbeats", async () => {
    const { scrollback } = scaffold({ pageVersion: "1.0.1", serverVersion: "1.1.0" })
    await start()
    expect(scrollback.querySelectorAll(".pito-turn").length).toBe(1)

    // A later heartbeat replaces the node — remount with a newer version still.
    const node2 = document.createElement("div")
    node2.setAttribute("data-controller", "pito--version-watch")
    node2.setAttribute("data-pito--version-watch-version-value", "1.2.0")
    document.body.appendChild(node2)
    await Promise.resolve()

    expect(scrollback.querySelectorAll(".pito-turn").length).toBe(1)
  })
})
