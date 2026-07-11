// spec/javascript/ai_accent_controller.test.js
//
// Vitest (jsdom) suite for pito--ai-accent: flips the chatbox Segment bar
// between the ai gradient and purple as soon as the textarea's value starts
// with the `ai` verb (word-boundary, case-insensitive, leading whitespace
// tolerated) — synced both on every input event and immediately on connect.

import { describe, it, expect, afterEach } from "vitest"
import { Application } from "@hotwired/stimulus"
import AiAccentController from "controllers/pito/ai_accent_controller"

function buildWrapper({ withBar = true, withField = true, value = "" } = {}) {
  const wrapper = document.createElement("div")
  wrapper.setAttribute("data-controller", "pito--ai-accent")

  if (withBar) {
    const bar = document.createElement("div")
    bar.className = "pito-segment__bar"
    bar.dataset.accent = "purple"
    wrapper.appendChild(bar)
  }

  if (withField) {
    const field = document.createElement("textarea")
    field.value = value
    wrapper.appendChild(field)
  }

  document.body.appendChild(wrapper)
  return wrapper
}

const bar = (wrapper) => wrapper.querySelector(".pito-segment__bar")
const field = (wrapper) => wrapper.querySelector("textarea")

function typeAndDispatch(wrapper, value) {
  field(wrapper).value = value
  field(wrapper).dispatchEvent(new Event("input", { bubbles: true }))
}

describe("pito--ai-accent controller", () => {
  let app

  async function mount(options) {
    const wrapper = buildWrapper(options)
    app = Application.start()
    app.register("pito--ai-accent", AiAccentController)
    await Promise.resolve()
    return wrapper
  }

  afterEach(async () => {
    document.body.innerHTML = ""
    await app.stop()
  })

  it('flips the bar to "ai" when the textarea starts with the ai verb', async () => {
    const wrapper = await mount()
    typeAndDispatch(wrapper, "ai what should I play")
    expect(bar(wrapper).dataset.accent).toBe("ai")
  })

  it("flips back to purple once the value no longer starts with ai", async () => {
    const wrapper = await mount()
    typeAndDispatch(wrapper, "ai what should I play")
    expect(bar(wrapper).dataset.accent).toBe("ai")

    typeAndDispatch(wrapper, "list vids")
    expect(bar(wrapper).dataset.accent).toBe("purple")
  })

  it("matches case-insensitively and with leading whitespace", async () => {
    const wrapper = await mount()

    typeAndDispatch(wrapper, "AI SOMETHING")
    expect(bar(wrapper).dataset.accent).toBe("ai")

    typeAndDispatch(wrapper, "  ai x")
    expect(bar(wrapper).dataset.accent).toBe("ai")
  })

  it("does not match on a word-boundary miss (aim high, chair)", async () => {
    const wrapper = await mount()

    typeAndDispatch(wrapper, "aim high")
    expect(bar(wrapper).dataset.accent).toBe("purple")

    typeAndDispatch(wrapper, "chair")
    expect(bar(wrapper).dataset.accent).toBe("purple")
  })

  it("syncs immediately on connect when the field is pre-filled", async () => {
    const wrapper = await mount({ value: "ai hi" })
    expect(bar(wrapper).dataset.accent).toBe("ai")
  })

  it("stays inert (no throw) when the bar is missing", async () => {
    const wrapper = await mount({ withBar: false })
    expect(() => typeAndDispatch(wrapper, "ai hi")).not.toThrow()
  })

  it("stays inert (no throw) when the field is missing", async () => {
    await expect(mount({ withField: false })).resolves.toBeTruthy()
  })
})
