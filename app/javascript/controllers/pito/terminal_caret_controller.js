// Pito::TerminalCaretController
//
// VERDICT: the ghost `Cursor::Component` is unsuitable as the chatbox
// caret — it is a fixed decorative "/" glyph that never tracks input and visually
// competes with the real (native) caret. A native caret cannot be a styled block
// (it is always a thin I-beam), and CSS `caret-shape: block` is not Baseline
// (~48% support) and cannot do the over-hint decoration or invert the covered glyph.
// Resolution: this controller draws a terminal-style BLOCK caret as an overlay.
//
// It hides the native caret and positions a blinking block over the glyph at the
// caret, inverting that glyph (bg-root on fg-default). When the field is empty the
// block sits over the first character of the placeholder hint (the rest of the hint
// shows faded behind it). The caret pixel position is computed with a hidden mirror
// element that replicates the field's font / width / wrapping, so the block lands on
// the correct soft-wrapped visual row and the field auto-grows in height.
//
// Reusable on any monospace <textarea> or <input> — the chatbox now, the Ctrl+K
// command palette later. Modern browsers only; no fallbacks (single-user app).
//
// Markup:
//   <div class="pito-chatbox__field-wrap" data-controller="pito--terminal-caret">
//     <textarea data-pito--terminal-caret-target="field" ...></textarea>
//     <span class="terminal-caret" data-pito--terminal-caret-target="block" aria-hidden="true"></span>
//   </div>

import { Controller } from "@hotwired/stimulus"

// Computed styles copied onto the mirror so its line-breaking matches the field.
const MIRRORED_STYLES = [
  "boxSizing", "width",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
  "fontFamily", "fontSize", "fontWeight", "fontStyle", "fontVariant",
  "letterSpacing", "wordSpacing", "lineHeight", "textTransform", "textIndent",
  "tabSize",
]

export default class extends Controller {
  static targets = ["field", "block"]
  static values = { autofocus: Boolean }

  connect() {
    this.field = this.hasFieldTarget ? this.fieldTarget : this.element
    this.#buildMirror()
    this.#syncBlockMetrics()
    this.#bind()
    this.autosize()
    if (this.autofocusValue) {
      this.field.focus({ preventScroll: true })
      // Restored drafts (and conversation switches) re-render the field with its
      // saved text; focus() alone leaves the caret at position 0. Move it to the
      // end so the user continues typing from where they left off.
      const end = this.field.value.length
      this.field.selectionStart = this.field.selectionEnd = end
    }
    this.#setActive(document.activeElement === this.field)
    this.render()
    // Emit initial focus state so a late-connecting chatbox-hints controller
    // gets the correct value even if it missed the autofocus event.
    this.#emitFocus(document.activeElement === this.field)
  }

  disconnect() {
    this.abort?.abort()
    this.resizeObserver?.disconnect()
    this.mirror?.remove()
  }

  // Grow the field's height to fit its (soft-wrapped) content, so wrapping makes the
  // chatbox taller instead of scrolling. Reset to "auto" first to allow shrinking.
  autosize() {
    this.field.style.height = "auto"
    this.field.style.height = `${this.field.scrollHeight}px`
  }

  // Position the block over the glyph at the caret and invert that glyph.
  render() {
    const value = this.field.value
    const empty = value.length === 0
    const index = empty ? 0 : (this.field.selectionStart ?? value.length)

    // The block covers the glyph to the RIGHT of the caret (terminal style).
    // Empty field -> first char of the hint. End of text -> nothing (plain block).
    let glyph
    if (empty) {
      glyph = (this.field.placeholder || "").charAt(0)
    } else {
      glyph = value.charAt(index)
    }

    const { left, top } = this.#caretCoords(index)
    this.blockTarget.style.transform = `translate(${left}px, ${top}px)`
    this.blockTarget.textContent = glyph && glyph !== "\n" ? glyph : " "
  }

  // Returns the current caret pixel position { left, top } relative to the
  // field's border box. Public so sibling controllers (e.g. pito--suggestions)
  // can read it on demand.
  caretCoords() {
    const value = this.field.value
    const empty = value.length === 0
    const index = empty ? 0 : (this.field.selectionStart ?? value.length)
    return this.#caretCoords(index)
  }

  // ── internals ──────────────────────────────────────────────────────────────

  #emitCaret() {
    const { left, top } = this.caretCoords()
    this.element.dispatchEvent(
      new CustomEvent("pito:caret", { bubbles: true, detail: { left, top } })
    )
  }

  // Dispatch a bubbling pito:focus event so chatbox-hints (and any other listener)
  // knows the current focus state of the chatbox field.
  #emitFocus(focused) {
    document.dispatchEvent(new CustomEvent("pito:focus", {
      bubbles: false,
      detail: { focused: !!focused },
    }))
  }

  #bind() {
    this.abort = new AbortController()
    const { signal } = this.abort
    const onCaretMove = () => { this.render(); this.#emitCaret() }
    const onInput = () => { this.autosize(); this.render(); this.#emitCaret() }
    const onFocus = () => { this.#setActive(true); this.#emitFocus(true); this.render(); this.#emitCaret() }
    const onBlur = () => { this.#setActive(false); this.#emitFocus(false); this.render() }

    this.field.addEventListener("input", onInput, { signal })
    this.field.addEventListener("keyup", onCaretMove, { signal })
    this.field.addEventListener("click", onCaretMove, { signal })
    this.field.addEventListener("focus", onFocus, { signal })
    this.field.addEventListener("blur", onBlur, { signal })
    this.field.addEventListener("scroll", onCaretMove, { signal })
    // `input` does not fire when the field is cleared programmatically (e.g. the
    // chat form on submit) — that path dispatches its own "input" event.
    document.addEventListener("selectionchange", () => {
      if (document.activeElement === this.field) { this.render(); this.#emitCaret() }
    }, { signal })

    // Re-sync mirror width + re-grow when the field is resized by layout.
    this.resizeObserver = new ResizeObserver(() => {
      this.mirror.style.width = getComputedStyle(this.field).width
      this.autosize()
      this.render()
    })
    this.resizeObserver.observe(this.field)
  }

  // Solid while the field is focused; blink only when it is not focused.
  #setActive(active) {
    this.blockTarget.toggleAttribute("data-focused", active)
  }

  // Returns the caret's pixel position relative to the field's border box,
  // adjusted for the field's own scroll offset.
  #caretCoords(index) {
    const value = this.field.value
    this.mirror.textContent = value.slice(0, index)
    const marker = document.createElement("span")
    // Non-empty content so the marker has a box even at end-of-line.
    marker.textContent = value.charAt(index) || "."
    this.mirror.appendChild(marker)
    const left = marker.offsetLeft - this.field.scrollLeft
    const top = marker.offsetTop - this.field.scrollTop
    this.mirror.removeChild(marker)
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
      whiteSpace: "pre-wrap",
      overflowWrap: "break-word",
      overflow: "hidden",
      pointerEvents: "none",
    })
    mirror.setAttribute("aria-hidden", "true")
    this.element.appendChild(mirror)
    this.mirror = mirror
  }

  // Match the block's line box to the field so the inverted glyph aligns.
  #syncBlockMetrics() {
    const cs = getComputedStyle(this.field)
    Object.assign(this.blockTarget.style, {
      height: cs.lineHeight,
      lineHeight: cs.lineHeight,
    })
  }
}
