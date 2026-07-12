// pito--selection-scope
//
// Scopes the mobile context menu's "Select all" to ONE message instead of the
// whole conversation. Long-pressing a word selects inside a message; native
// Select all then re-anchors the selection at the very top of the page and
// swallows everything.
//
// The clamp watches selectionchange: while a selection lives inside a single
// [data-scrollback-message], that message is remembered as the active one.
// When the anchor then JUMPS OUTSIDE it while the new selection still
// swallows the whole remembered message — the select-all signature — the
// selection is re-scoped to exactly that message. A manual cross-message drag
// keeps its anchor where the drag started (inside the remembered message), so
// it is never clamped; selections that don't contain the remembered message
// are someone else's business and are left alone too.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onSelectionChange = this.selectionChanged.bind(this)
    this.onSelectStart = this.selectStarted.bind(this)
    document.addEventListener("selectionchange", this.onSelectionChange)
    document.addEventListener("selectstart", this.onSelectStart)
  }

  disconnect() {
    document.removeEventListener("selectionchange", this.onSelectionChange)
    document.removeEventListener("selectstart", this.onSelectStart)
  }

  // The flash-free path: select-all re-associates the selection at the TOP of
  // the document, and `selectstart` fires at that cancelable moment — BEFORE
  // the page-wide selection ever paints. With an in-message selection active
  // and the new one starting OUTSIDE any message, cancel it and select the
  // remembered message directly. A fresh drag beginning INSIDE a message
  // targets message content, so it is never intercepted; engines whose menu
  // skips selectstart still get the reactive selectionchange clamp below.
  selectStarted(event) {
    const active = this.activeMessage
    if (!active || !active.isConnected) return
    if (this.messageOf(event.target)) return

    event.preventDefault()
    this.clamping = true
    document.getSelection()?.selectAllChildren(active)
    requestAnimationFrame(() => { this.clamping = false })
  }

  selectionChanged() {
    if (this.clamping) return
    const selection = document.getSelection()
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return

    const anchorMessage = this.messageOf(selection.anchorNode)
    const focusMessage = this.messageOf(selection.focusNode)

    // In-message selection (the long-pressed word): remember its message.
    if (anchorMessage && anchorMessage === focusMessage) {
      this.activeMessage = anchorMessage
      return
    }

    const active = this.activeMessage
    if (!active || !active.isConnected) return
    // Anchor still where the user started dragging → a legit multi-message
    // drag, never clamped.
    if (anchorMessage === active) return
    // Selection doesn't even cover the remembered message → unrelated.
    if (!selection.containsNode(active, false)) return

    // Select-all signature: re-scope to the message the gesture began in.
    this.clamping = true
    selection.selectAllChildren(active)
    requestAnimationFrame(() => { this.clamping = false })
  }

  messageOf(node) {
    if (!node) return null
    const el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement
    return el ? el.closest("[data-scrollback-message]") : null
  }
}
