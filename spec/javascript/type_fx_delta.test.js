// spec/javascript/type_fx_delta.test.js
//
// Pure-logic tests for the delta-diff algorithm described in type_fx_controller.js.
//
// The algorithm finds the common prefix (p) and common suffix (s) between
// prevValue and newValue, then replaces only the changed run in the middle.
//
// We extract the algorithm into a pure function for unit testing WITHOUT
// requiring a real DOM textarea + overlay — the controller itself is too
// tightly coupled to getComputedStyle / ResizeObserver for an isolated unit
// test.  Instead we re-implement the boundary-finding logic as a pure helper
// and verify it matches the spec in the controller's source.

import { describe, it, expect } from "vitest"

// Extract the prefix/suffix calculation as a pure function (mirrors the
// #deltaRender logic in type_fx_controller.js).
function computeDelta(prev, next) {
  const pLen = prev.length
  const nLen = next.length
  const minLen = Math.min(pLen, nLen)

  let p = 0
  while (p < minLen && prev[p] === next[p]) p++

  let s = 0
  while (
    s < pLen - p &&
    s < nLen - p &&
    prev[pLen - 1 - s] === next[nLen - 1 - s]
  ) s++

  return {
    prefixLen:     p,
    suffixLen:     s,
    removedRun:    prev.slice(p, pLen - s),
    insertedRun:   next.slice(p, nLen - s),
  }
}

describe("type_fx delta-diff algorithm", () => {
  // ── Single character append ──────────────────────────────────────────────
  it("appending one char: prefix = full old string, empty removed run", () => {
    const { prefixLen, removedRun, insertedRun, suffixLen } = computeDelta("abc", "abcd")
    expect(prefixLen).toBe(3)
    expect(suffixLen).toBe(0)
    expect(removedRun).toBe("")
    expect(insertedRun).toBe("d")
  })

  // ── Single character backspace ───────────────────────────────────────────
  it("deleting last char: suffix = empty, removed = last char", () => {
    const { prefixLen, removedRun, insertedRun, suffixLen } = computeDelta("abcd", "abc")
    expect(prefixLen).toBe(3)
    expect(suffixLen).toBe(0)
    expect(removedRun).toBe("d")
    expect(insertedRun).toBe("")
  })

  // ── Middle insertion ─────────────────────────────────────────────────────
  it("inserting in the middle: prefix + suffix correctly identify the run", () => {
    const { prefixLen, removedRun, insertedRun, suffixLen } = computeDelta("abef", "abcdef")
    expect(prefixLen).toBe(2)
    expect(suffixLen).toBe(2)
    expect(removedRun).toBe("")
    expect(insertedRun).toBe("cd")
  })

  // ── Middle replacement ───────────────────────────────────────────────────
  it("replacing the middle: prefix and suffix shrink to the changed run", () => {
    const { removedRun, insertedRun } = computeDelta("aXXd", "aYYd")
    expect(removedRun).toBe("XX")
    expect(insertedRun).toBe("YY")
  })

  // ── Full replacement ─────────────────────────────────────────────────────
  it("completely different strings: prefix=0, suffix=0", () => {
    const { prefixLen, suffixLen } = computeDelta("abc", "xyz")
    expect(prefixLen).toBe(0)
    expect(suffixLen).toBe(0)
  })

  // ── Identical strings ────────────────────────────────────────────────────
  it("identical strings: prefix = entire length, no run", () => {
    const { prefixLen, removedRun, insertedRun } = computeDelta("hello", "hello")
    expect(prefixLen).toBe(5)
    expect(removedRun).toBe("")
    expect(insertedRun).toBe("")
  })

  // ── Empty prev / new ─────────────────────────────────────────────────────
  it("prev empty → prefix=0, entire new string is inserted run", () => {
    const { prefixLen, insertedRun } = computeDelta("", "hello")
    expect(prefixLen).toBe(0)
    expect(insertedRun).toBe("hello")
  })

  it("new empty → removed run is entire prev string", () => {
    const { removedRun, insertedRun } = computeDelta("hello", "")
    expect(removedRun).toBe("hello")
    expect(insertedRun).toBe("")
  })

  // ── Suffix-only deletion (delete key at start) ───────────────────────────
  it("deleting leading char: prefix=0, suffix = remaining length", () => {
    const { prefixLen, suffixLen, removedRun } = computeDelta("Xhello", "hello")
    expect(prefixLen).toBe(0)
    expect(suffixLen).toBe(5)
    expect(removedRun).toBe("X")
  })

  // ── Unicode (multi-codepoint characters handled as JS chars) ────────────
  it("emoji append: treats emoji as JS code unit sequence", () => {
    const base = "hi"
    const withEmoji = "hi😀"
    const { prefixLen, insertedRun } = computeDelta(base, withEmoji)
    expect(prefixLen).toBe(2)
    expect(insertedRun).toBe("😀")
  })
})
