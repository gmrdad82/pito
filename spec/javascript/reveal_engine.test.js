// spec/javascript/reveal_engine.test.js
//
// FX: typewriter first-glyph priming. The typewriter prime prefills the first
// glyph so the box reserves layout while it waits for its reveal slot — but a
// fully-opaque prefill "pops" visibly before the reveal starts. The engine dims
// that glyph to ~invisible (PRIME_OPACITY) at prime and snaps it back to full the
// moment the run begins. Scramble/comet are unaffected.

import { describe, it, expect, afterEach } from "vitest"
import { RevealEngine, PRIME_OPACITY } from "pito/reveal_engine"

function bodyWith(text) {
  const el = document.createElement("p")
  el.textContent = text
  document.body.appendChild(el)
  return el
}

function primedEngine(el, effect) {
  const engine = new RevealEngine([el])
  engine.collect()
  engine.prime(effect)
  return engine
}

afterEach(() => { document.body.innerHTML = "" })

describe("RevealEngine — typewriter first-glyph prime (FX)", () => {
  it("reserves layout (first char) but dims it to ~invisible on prime", () => {
    const el = bodyWith("hello world")
    primedEngine(el, "typewriter")

    expect(el.textContent).toBe("h")                       // layout reserved
    expect(el.style.opacity).toBe(String(PRIME_OPACITY))   // but invisible (no pop)
  })

  it("snaps the first glyph to full opacity when the reveal runs", async () => {
    const el = bodyWith("hello world")
    const engine = primedEngine(el, "typewriter")
    expect(el.style.opacity).toBe(String(PRIME_OPACITY))

    const done = engine.run("typewriter")
    expect(el.style.opacity).toBe("")                      // hard snap as the run begins

    await done
    expect(el.textContent).toBe("hello world")
  })

  it("clears the prime dim on an instant finish (backpressure / skip)", () => {
    const el = bodyWith("hello world")
    const engine = primedEngine(el, "typewriter")

    engine.finishInstant()
    expect(el.style.opacity).toBe("")
    expect(el.textContent).toBe("hello world")
  })

  it("clears the prime dim on cancel (e.g. element swapped mid-reveal)", () => {
    const el = bodyWith("hello world")
    const engine = primedEngine(el, "typewriter")

    engine.cancel()
    expect(el.style.opacity).toBe("")
  })

  it("does NOT apply the typewriter prime dim under scramble or comet", () => {
    const scram = bodyWith("scrambled")
    primedEngine(scram, "scramble")
    expect(scram.style.opacity).not.toBe(String(PRIME_OPACITY))

    const comet = bodyWith("comet text")
    primedEngine(comet, "comet")
    // comet dims to its OWN value (0.01), never PRIME_OPACITY
    expect(comet.style.opacity).not.toBe(String(PRIME_OPACITY))
  })
})
