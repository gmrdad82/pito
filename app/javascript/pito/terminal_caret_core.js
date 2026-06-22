// Pito terminal-caret CORE (shared, controller-agnostic)
//
// Extracted from Pito::TerminalCaretController so the same block-caret machinery
// drives the multi-line chatbox <textarea> AND the single-line sidebar / palette
// <input>s. It owns: the hidden mirror (caret pixel-coord math), the inverted
// block render, focus/visibility toggling, and the bubbling `pito:caret` emit.
//
// It does NOT bind DOM events, intercept keys, or read settings — the wrapping
// Stimulus controller does that. Keeping the core render-only preserves the
// ctrl+k palette + sidebar arrow/Enter arbitration and IME/mobile composition.
//
// Two modes (auto-detected from the field's tagName, override via `mode`):
//   "textarea" — multi-line: mirror wraps (`white-space: pre-wrap`), height
//                auto-grows via autosize(), caret can land on any wrapped row.
//   "input"    — single-line: no autosize, mirror never wraps (`white-space:
//                pre`, top always 0), and the field's horizontal `scrollLeft`
//                is subtracted so the block tracks past the visible left edge.

// Computed styles copied onto the mirror so its line-breaking matches the field.
export const MIRRORED_STYLES = [
  "boxSizing", "width",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
  "fontFamily", "fontSize", "fontWeight", "fontStyle", "fontVariant",
  "letterSpacing", "wordSpacing", "lineHeight", "textTransform", "textIndent",
  "tabSize",
]

export default class TerminalCaretCore {
  // opts:
  //   field — the <textarea>/<input> the caret tracks
  //   block — the .terminal-caret span overlay
  //   host  — element the mirror is appended to + `pito:caret` dispatched from
  //   mode  — "textarea" | "input" (optional; auto-detected from field.tagName)
  constructor({ field, block, host, mode }) {
    this.field = field
    this.block = block
    this.host = host
    this.mode = mode || (field.tagName === "INPUT" ? "input" : "textarea")
  }

  get singleLine() {
    return this.mode === "input"
  }

  mount() {
    this.#buildMirror()
    this.#syncBlockMetrics()
  }

  teardown() {
    this.mirror?.remove()
  }

  // Grow a textarea to fit its (soft-wrapped) content. No-op for single-line
  // inputs — they never change height.
  autosize() {
    if (this.singleLine) return
    this.field.style.height = "auto"
    this.field.style.height = `${this.field.scrollHeight}px`
  }

  // Position the block over the glyph at the caret and invert that glyph.
  render() {
    const value = this.field.value
    const empty = value.length === 0
    const index = empty ? 0 : (this.field.selectionStart ?? value.length)

    // The block covers the glyph to the RIGHT of the caret (terminal style).
    // Empty field -> first char of the hint. End of text -> plain block.
    let glyph
    if (empty) {
      glyph = (this.field.placeholder || "").charAt(0)
    } else {
      glyph = value.charAt(index)
    }

    const coords = this.#caretCoords(index)
    // Cache the measurement for the emitCaret() that pairs with this render()
    // (callers always do render()+emitCaret() in one tick) so the trail/ghost
    // siblings don't trigger a SECOND synchronous reflow per keystroke.
    this._coords = coords
    this.block.style.transform = `translate(${coords.left}px, ${coords.top}px)`
    this.block.textContent = glyph && glyph !== "\n" ? glyph : " "
  }

  // Current caret pixel position { left, top } relative to the field border box.
  caretCoords() {
    const value = this.field.value
    const empty = value.length === 0
    const index = empty ? 0 : (this.field.selectionStart ?? value.length)
    return this.#caretCoords(index)
  }

  // Bubbling `pito:caret` so sibling controllers (suggestions, cursor-trail)
  // can react without forking the caret machinery. Reuses the coords render()
  // just measured this tick (no double reflow); falls back to a fresh measure
  // if emit is ever called without a preceding render().
  emitCaret() {
    const { left, top } = this._coords ?? this.caretCoords()
    this._coords = null
    this.host.dispatchEvent(
      new CustomEvent("pito:caret", { bubbles: true, detail: { left, top } })
    )
  }

  // Solid (no blink) while focused; blink only when blurred. (textarea blink is
  // gated by the controller via [data-no-blink] when motion is off.)
  setActive(active) {
    this.block.toggleAttribute("data-focused", active)
  }

  // Single-line mode only: show the block ONLY for the focused input so we never
  // paint five carets at once across the sidebar/palette inputs.
  setVisible(visible) {
    this.block.toggleAttribute("hidden", !visible)
  }

  // Re-sync the mirror width to the (possibly resized) field.
  syncMirrorWidth() {
    this.mirror.style.width = getComputedStyle(this.field).width
  }

  // ── internals ──────────────────────────────────────────────────────────────

  // Caret pixel position relative to the field border box, adjusted for the
  // field's own scroll offset (horizontal for inputs, vertical for textareas).
  // Updates the persistent text-node + marker built in #buildMirror rather than
  // creating/removing a marker element every keystroke (no per-input DOM churn).
  #caretCoords(index) {
    const value = this.field.value
    this.mirrorText.data = value.slice(0, index)
    // Non-empty content so the marker has a box even at end-of-line.
    this.marker.textContent = value.charAt(index) || "."
    const left = this.marker.offsetLeft - this.field.scrollLeft
    const top = this.marker.offsetTop - this.field.scrollTop
    return { left, top }
  }

  #buildMirror() {
    const mirror = document.createElement("div")
    const cs = getComputedStyle(this.field)
    for (const prop of MIRRORED_STYLES) mirror.style[prop] = cs[prop]
    Object.assign(mirror.style, {
      position: "absolute",
      top: "0",
      left: "0",
      visibility: "hidden",
      // Single-line never wraps (top stays 0); multi-line wraps like the field.
      whiteSpace: this.singleLine ? "pre" : "pre-wrap",
      overflowWrap: this.singleLine ? "normal" : "break-word",
      overflow: "hidden",
      pointerEvents: "none",
    })
    mirror.setAttribute("aria-hidden", "true")

    // Persistent measuring rig: a text node carrying the value-up-to-caret and a
    // marker span standing in for the glyph at the caret. #caretCoords only
    // updates their contents — the mirror itself is built ONCE (never per input).
    this.mirrorText = document.createTextNode("")
    this.marker = document.createElement("span")
    mirror.appendChild(this.mirrorText)
    mirror.appendChild(this.marker)

    this.host.appendChild(mirror)
    this.mirror = mirror
  }

  // Match the block's line box to the field so the inverted glyph aligns.
  #syncBlockMetrics() {
    const cs = getComputedStyle(this.field)
    Object.assign(this.block.style, {
      height: cs.lineHeight,
      lineHeight: cs.lineHeight,
    })
  }
}
