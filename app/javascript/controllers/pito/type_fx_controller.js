// Pito::TypeFxController
//
// Overlays the native textarea with a per-character animation layer so that
// each newly typed (or auto-inserted) character fades + rises into view.
// The native <textarea> remains the single source of truth for value,
// selection, and submit — the overlay is purely decorative.
//
// Architecture:
//   • A `.pito-type-layer` div mirrors the textarea's font/padding/width
//     exactly (same mirror technique pito--suggestions uses for the ghost) and
//     sits above the transparent textarea at z-index:1.
//   • The textarea gets `.is-fx` → `color:transparent` so only the overlay
//     is visible, but the native selection highlight still renders.
//   • Each code-point is wrapped in a `<span class="pito-type-char">`.
//     Newly inserted characters also get `.pito-type-char--new` which
//     triggers the CSS `pito-char-in` animation; the class is stripped after
//     the animation ends (or after a 150 ms safety timeout) so re-renders
//     don't re-animate settled characters.
//
// Delta rendering (F1.3 – O(delta) not O(n)):
//   prevValue vs newValue → find common prefix length (p) and common suffix
//   length (s, measured from the END).  The changed run in prevValue is
//   spans[p .. N-s], in newValue it is chars[p .. M-s].  Only that slice is
//   mutated; unchanged leading and trailing spans are left alone.
//
// IME / paste (F1.5):
//   • compositionstart → sets this.composing = true; updates are paused.
//   • compositionend   → clears flag, does one clean delta render (no --new).
//   • paste of > 40 chars → renders the pasted run plain (no per-char --new).
//
// Reduced-motion (F1.5):
//   connect() returns early when prefers-reduced-motion matches; the CSS also
//   re-shows native text and hides the layer as a belt-and-suspenders guard.
//
// Coexistence (F1.5):
//   z-order: textarea (auto) < .pito-type-layer (1) < .pito-ghost (2)
//   The caret is the browser's native block caret (CSS .pito-block-caret); the
//   suggestions controller's ghost layer is unmodified.

import { Controller } from "@hotwired/stimulus"
import { fxEnabled } from "pito/settings"
import { TICK_MS } from "pito/typing"  // shared cadence reference (animation itself is CSS-driven)

// Computed styles to copy onto the overlay so wrapping matches the textarea.
// Same list as the caret mirror in suggestions_controller.js — keep in sync.
const MIRRORED_STYLES = [
  "boxSizing", "width",
  "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
  "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
  "fontFamily", "fontSize", "fontWeight", "fontStyle", "fontVariant",
  "letterSpacing", "wordSpacing", "lineHeight", "textTransform", "textIndent",
  "tabSize",
]

// Large-paste threshold: pastes longer than this skip per-char animation.
const LARGE_PASTE_THRESHOLD = 40

export default class extends Controller {
  static targets = ["field"]

  connect() {
    // Reduced-motion or fx-off opt-out: leave native textarea fully visible.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    if (!fxEnabled()) return

    this.field = this.hasFieldTarget
      ? this.fieldTarget
      : this.element.querySelector("textarea, input")
    if (!this.field) return

    this.prevValue  = this.field.value
    this.composing  = false
    this.pasteSize  = 0  // set by paste handler, read by next input handler

    this.#buildLayer()
    this.#renderAll(this.field.value, false)
    this.field.classList.add("is-fx")
    this.#bind()
  }

  disconnect() {
    this.abort?.abort()
    this.resizeObserver?.disconnect()
    this.layer?.remove()
    this.field?.classList.remove("is-fx")
  }

  // ── private ────────────────────────────────────────────────────────────────

  // Build the visible character overlay div.
  #buildLayer() {
    const layer = document.createElement("div")
    layer.className = "pito-type-layer"
    layer.setAttribute("aria-hidden", "true")

    const cs = getComputedStyle(this.field)
    for (const prop of MIRRORED_STYLES) layer.style[prop] = cs[prop]
    // Position: flush with the textarea's content origin.
    Object.assign(layer.style, {
      top:   "0",
      left:  "0",
      color: cs.color,
    })

    this.element.appendChild(layer)
    this.layer = layer
  }

  // Bind input/composition/paste listeners and a ResizeObserver.
  #bind() {
    this.abort = new AbortController()
    const { signal } = this.abort

    this.field.addEventListener("compositionstart", () => {
      this.composing = true
    }, { signal })

    this.field.addEventListener("compositionend", () => {
      this.composing = false
      // After IME commit, do a clean delta render (no animation).
      this.#deltaRender(this.field.value, false)
      this.prevValue = this.field.value
    }, { signal })

    this.field.addEventListener("paste", (e) => {
      // Record how many characters are being pasted so the next input
      // handler can decide whether to animate or not.
      const text = e.clipboardData?.getData("text") ?? ""
      this.pasteSize = text.length
    }, { signal })

    this.field.addEventListener("input", () => {
      if (this.composing) return  // wait for compositionend

      const newValue   = this.field.value
      const isLargePaste = this.pasteSize > LARGE_PASTE_THRESHOLD
      this.pasteSize   = 0       // consume

      this.#deltaRender(newValue, !isLargePaste)
      this.prevValue = newValue
    }, { signal })

    // Keep overlay width in sync when the field is resized (e.g. textarea grows).
    this.resizeObserver = new ResizeObserver(() => {
      const cs = getComputedStyle(this.field)
      this.layer.style.width = cs.width
    })
    this.resizeObserver.observe(this.field)
  }

  // Full render — used on connect() for the initial value.
  #renderAll(value, animate) {
    this.layer.textContent = ""
    const frag = document.createDocumentFragment()
    for (const ch of value) {
      frag.appendChild(this.#makeSpan(ch, animate))
    }
    this.layer.appendChild(frag)
  }

  // Delta render — O(changed chars), not O(n).
  // Finds the common prefix and common suffix and only replaces the middle run.
  #deltaRender(newValue, animate) {
    const prev = this.prevValue
    const spans = this.layer.children  // HTMLCollection (live)

    if (newValue === prev) return  // nothing changed

    const pLen = prev.length
    const nLen = newValue.length

    // Common prefix length (p).
    let p = 0
    const minLen = Math.min(pLen, nLen)
    while (p < minLen && prev[p] === newValue[p]) p++

    // Common suffix length (s), measured from the END of both strings.
    let s = 0
    while (
      s < pLen - p &&
      s < nLen - p &&
      prev[pLen - 1 - s] === newValue[nLen - 1 - s]
    ) s++

    // Remove old changed-run spans (from index p up to but not including pLen-s).
    const removeCount = pLen - p - s
    for (let i = 0; i < removeCount; i++) {
      // After each remove, spans[p] is the next span in the changed run.
      const toRemove = spans[p]
      if (toRemove) this.layer.removeChild(toRemove)
    }

    // Insert new changed-run spans at position p (before the first suffix span).
    const insertCount = nLen - p - s
    if (insertCount > 0) {
      const anchor = spans[p] ?? null  // null → append
      const frag = document.createDocumentFragment()
      for (let i = 0; i < insertCount; i++) {
        frag.appendChild(this.#makeSpan(newValue[p + i], animate))
      }
      this.layer.insertBefore(frag, anchor)
    }
  }

  // Create a single character span.
  // animate=true: add --new and strip it after animation ends (or 150ms timeout).
  #makeSpan(ch, animate) {
    const span = document.createElement("span")
    span.className = "pito-type-char"
    // white-space:pre-wrap on the layer handles spaces and newlines correctly.
    span.textContent = ch

    if (animate && ch !== "\n") {
      span.classList.add("pito-type-char--new")
      const strip = () => span.classList.remove("pito-type-char--new")
      span.addEventListener("animationend", strip, { once: true })
      // Safety: strip even if the animation never fires (e.g. tab hidden).
      // ~150 ms — roughly TICK_MS * 12 — long enough for the CSS animation.
      setTimeout(strip, TICK_MS * 12)
    }

    return span
  }
}
