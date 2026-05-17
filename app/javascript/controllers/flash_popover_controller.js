import { Controller } from "@hotwired/stimulus"

// Promotes the `.toast-container` flash region into the browser's TOP LAYER
// via the native Popover API (`popover="manual"`) so flash toasts render
// ABOVE any open `<dialog>` (bundle modal, IGDB modal, TOTP modal, revoke
// confirm, Discord help, etc.). Plain `z-index` cannot beat top-layer
// content; only popover (or another `.showModal()` dialog) can.
//
// Top-layer stacking rule the browser enforces: the LAST element to enter
// the top layer renders above earlier ones. When a flash fires AFTER a
// modal is already open, the `showPopover()` call here promotes this
// container above the modal automatically.
//
// Lifecycle:
//   * `connect()` — if the server-side flash render already left toasts in
//     the DOM, show the popover immediately. Otherwise stay hidden so
//     empty containers do not paint a frame.
//   * MutationObserver on `childList` — when a JS controller (e.g.
//     `inline_title_edit`, `clipboard_copy`) appends a new toast, ensure
//     the popover is open. When the last toast is removed (by
//     `toast_controller#dismiss`), hide the popover so the next
//     `showPopover()` call re-enters the top layer cleanly (browsers
//     ignore a duplicate `showPopover()` call but the re-enter is what
//     guarantees stacking above modals opened in the interim).
export default class extends Controller {
  connect() {
    this._showIfHasToasts()
    this._observer = new MutationObserver(() => this._reconcile())
    this._observer.observe(this.element, { childList: true })
  }

  disconnect() {
    if (this._observer) {
      this._observer.disconnect()
      this._observer = null
    }
    this._hideIfOpen()
  }

  _reconcile() {
    if (this._hasToasts()) {
      this._show()
    } else {
      this._hideIfOpen()
    }
  }

  _showIfHasToasts() {
    if (this._hasToasts()) this._show()
  }

  _show() {
    // Guard against environments where the Popover API is unsupported
    // (older browsers). The element still renders fixed-position by CSS so
    // flashes remain visible there — they just won't beat modals. The
    // Pito browser-support floor is Chrome 114+ / Firefox 125+ / Safari
    // 17+, all of which ship the Popover API; this guard is belt-and-
    // braces for hostile UA shims.
    if (typeof this.element.showPopover !== "function") return
    // `showPopover()` throws if already open; guard via `:popover-open`.
    if (this.element.matches(":popover-open")) {
      // Re-enter the top layer so stacking jumps above any modal opened
      // since the popover was first shown. The spec says calling
      // `showPopover()` on an already-open popover is a no-op (throws
      // `InvalidStateError`), so we hide + show to force the re-promote.
      try { this.element.hidePopover() } catch (_) { /* swallow */ }
    }
    try { this.element.showPopover() } catch (_) { /* swallow */ }
  }

  _hideIfOpen() {
    if (typeof this.element.hidePopover !== "function") return
    if (!this.element.matches(":popover-open")) return
    try { this.element.hidePopover() } catch (_) { /* swallow */ }
  }

  _hasToasts() {
    return this.element.querySelector(".toast") !== null
  }
}
