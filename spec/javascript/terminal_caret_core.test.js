// spec/javascript/terminal_caret_core.test.js
//
// Vitest suite for the shared TerminalCaretCore — focused on the single-line
// "input" mode added for the sidebar / palette / rename inputs.
//
// jsdom has no layout engine, so offsetLeft/offsetTop are 0. We therefore assert
// the *math the core applies on top of* those offsets: the horizontal scrollLeft
// subtraction (the load-bearing input-mode behaviour), mode auto-detection,
// focus-only visibility, glyph inversion, autosize suppression, and teardown.

import { describe, it, expect, beforeEach, afterEach } from "vitest"
import TerminalCaretCore from "pito/terminal_caret_core"

function build(tag, { value = "", placeholder = "" } = {}) {
  const host = document.createElement("div")
  const field = document.createElement(tag === "input" ? "input" : "textarea")
  if (tag === "input") field.type = "text"
  field.value = value
  if (placeholder) field.placeholder = placeholder
  const block = document.createElement("span")
  block.className = "terminal-caret"
  host.appendChild(field)
  host.appendChild(block)
  document.body.appendChild(host)
  return { host, field, block }
}

describe("TerminalCaretCore", () => {
  afterEach(() => { document.body.innerHTML = "" })

  describe("mode auto-detection", () => {
    it("treats an <input> as single-line", () => {
      const { host, field, block } = build("input")
      const core = new TerminalCaretCore({ field, block, host })
      expect(core.singleLine).toBe(true)
    })

    it("treats a <textarea> as multi-line", () => {
      const { host, field, block } = build("textarea")
      const core = new TerminalCaretCore({ field, block, host })
      expect(core.singleLine).toBe(false)
    })

    it("honours an explicit mode override", () => {
      const { host, field, block } = build("textarea")
      const core = new TerminalCaretCore({ field, block, host, mode: "input" })
      expect(core.singleLine).toBe(true)
    })
  })

  describe("input mode coord math", () => {
    let core, field

    beforeEach(() => {
      const built = build("input", { value: "hello world" })
      field = built.field
      core = new TerminalCaretCore({ field, block: built.block, host: built.host })
      core.mount()
    })

    it("subtracts the input's horizontal scrollLeft from the caret left", () => {
      field.selectionStart = field.selectionEnd = 6
      field.scrollLeft = 25 // input scrolled right (caret past the visible left edge)
      // offsetLeft is 0 in jsdom, so left collapses to -scrollLeft — proving the
      // horizontal-scroll accounting that the textarea path also relies on.
      expect(core.caretCoords().left).toBe(-25)
    })

    it("keeps top at 0 for single-line (no vertical scroll contribution)", () => {
      field.selectionStart = field.selectionEnd = 3
      field.scrollLeft = 40
      expect(core.caretCoords().top).toBe(0)
    })

    it("builds the mirror with white-space:pre so it never wraps", () => {
      expect(core.mirror.style.whiteSpace).toBe("pre")
    })
  })

  describe("multi-line mirror", () => {
    it("builds the mirror with white-space:pre-wrap so it wraps like the field", () => {
      const { host, field, block } = build("textarea")
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      expect(core.mirror.style.whiteSpace).toBe("pre-wrap")
    })
  })

  describe("render / glyph inversion", () => {
    it("draws the glyph to the right of the caret into the block", () => {
      const { host, field, block } = build("input", { value: "abc" })
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      field.selectionStart = field.selectionEnd = 1
      core.render()
      expect(block.textContent).toBe("b")
      expect(block.style.transform).toMatch(/^translate\(/)
    })

    it("uses the first placeholder glyph when the field is empty", () => {
      const { host, field, block } = build("input", { placeholder: "Search…" })
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      core.render()
      expect(block.textContent).toBe("S")
    })
  })

  describe("focus-only visibility (input mode)", () => {
    it("hides the block when not visible and shows it when visible", () => {
      const { host, field, block } = build("input")
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      core.setVisible(false)
      expect(block.hasAttribute("hidden")).toBe(true)
      core.setVisible(true)
      expect(block.hasAttribute("hidden")).toBe(false)
    })
  })

  describe("autosize", () => {
    it("is a no-op for single-line inputs (never sets height)", () => {
      const { host, field, block } = build("input", { value: "x" })
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      core.autosize()
      expect(field.style.height).toBe("")
    })
  })

  describe("mirror reuse (per-keystroke cost)", () => {
    it("builds the mirror + marker ONCE and reuses them across renders", () => {
      const { host, field, block } = build("textarea", { value: "abc" })
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()

      const mirror = core.mirror
      const marker = core.marker
      expect(mirror).toBeTruthy()
      expect(marker).toBeTruthy()

      // Simulate rapid typing: each render must NOT rebuild the mirror or churn
      // a fresh marker element (the old code created/removed a span per measure).
      for (let i = 0; i < 25; i++) {
        field.value = "abc".repeat(i + 1)
        field.selectionStart = field.selectionEnd = field.value.length
        core.render()
        expect(core.mirror).toBe(mirror)   // same mirror node, never rebuilt
        expect(core.marker).toBe(marker)   // same marker node, never recreated
      }
      // The mirror holds exactly its persistent rig (text node + the one marker).
      expect(mirror.querySelectorAll("span").length).toBe(1)
      // The block caret stays present + rendered with content (visible glyph).
      expect(block.textContent.length).toBeGreaterThan(0)
    })

    it("emitCaret reuses the coords render() just measured (no second reflow)", () => {
      const { host, field, block } = build("input", { value: "hello" })
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      field.selectionStart = field.selectionEnd = 5
      field.scrollLeft = 0

      let detail = null
      host.addEventListener("pito:caret", (e) => { detail = e.detail })

      core.render()
      const cached = core._coords
      expect(cached).toBeTruthy()
      core.emitCaret()
      expect(detail).toEqual(cached) // emitted coords are render()'s cached ones
      expect(core._coords).toBeNull() // cache consumed (won't go stale)
    })
  })

  describe("teardown", () => {
    it("removes the mirror from the host with no leaks", () => {
      const { host, field, block } = build("input")
      const core = new TerminalCaretCore({ field, block, host })
      core.mount()
      expect(host.contains(core.mirror)).toBe(true)
      core.teardown()
      expect(host.querySelectorAll("div").length).toBe(0)
    })
  })
})
