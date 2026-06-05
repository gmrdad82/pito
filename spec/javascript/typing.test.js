// spec/javascript/typing.test.js
//
// Sanity / shared-constant guard for pito/typing.js.
// These tests pin the exported values so any accidental change to the
// animation cadence is immediately visible in CI.

import { describe, it, expect } from "vitest"
import { TICK_MS, CHARS_TICK } from "pito/typing"

describe("pito/typing constants", () => {
  it("exports TICK_MS as a positive number", () => {
    expect(typeof TICK_MS).toBe("number")
    expect(TICK_MS).toBeGreaterThan(0)
  })

  it("exports CHARS_TICK as a positive integer", () => {
    expect(typeof CHARS_TICK).toBe("number")
    expect(CHARS_TICK).toBeGreaterThan(0)
    expect(Number.isInteger(CHARS_TICK)).toBe(true)
  })

  it("TICK_MS is 12 (shared cadence guard)", () => {
    expect(TICK_MS).toBe(12)
  })

  it("CHARS_TICK is 2 (shared cadence guard)", () => {
    expect(CHARS_TICK).toBe(2)
  })
})
