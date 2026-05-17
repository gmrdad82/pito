import { Controller } from "@hotwired/stimulus"

// 2026-05-17 — App-wide dialog scroll lock.
//
// Mounted ONCE on `<body>` in the application layout. While any
// `<dialog>` anywhere in the DOM is open (modals, confirm overlays,
// the leader-menu popup, /settings [help] modals, future ones), the
// page's vertical scroll is locked so wheel / touch / keyboard input
// can't scroll the page behind the modal. On dismissal — via any path
// (close button, ESC, click-outside, programmatic `.close()`) — page
// scroll is restored.
//
// Why a body-level controller + MutationObserver instead of per-modal
// wiring:
//   * Per-modal wiring would require editing every modal partial —
//     `/settings` is off-limits during the beta-3 lock, and we'd still
//     miss any future modal that forgets to opt in. A body-level
//     observer on the `open` attribute catches every `<dialog>`
//     uniformly regardless of how it was opened (`.showModal()`,
//     `.show()`, declarative `[open]`).
//   * Monkey-patching `HTMLDialogElement.prototype.showModal` is
//     fragile (per the rails-impl spec) and skips declarative opens.
//
// Nested dialogs: a `<dialog>` can open on top of another `<dialog>`
// (e.g. a [delete] confirm inside the bundle edit modal). We track an
// OPEN COUNT, not a boolean, so the page stays locked until ALL
// dialogs have closed.
//
// Jump prevention: paired with `html { scrollbar-gutter: stable }` in
// `application.css` — the scrollbar gutter is always reserved, so
// flipping `body { overflow: hidden }` does not shift content right
// by the scrollbar's width when the lock engages.
//
// The lock flag is `body[data-modal-open]` (matched by a CSS rule in
// `application.css` — `body[data-modal-open] { overflow: hidden; }`).
// Using a data-attribute instead of a class keeps the surface visible
// to anyone grepping for "modal-open" and avoids collision with
// arbitrary utility classes.
//
// NO JS `confirm()` / `alert()` / `prompt()` (CLAUDE.md hard rule).
export default class extends Controller {
  connect() {
    this.openCount = 0

    // 1) MutationObserver — primary open/close detector. Watches the
    //    `open` attribute on every descendant; fires synchronously on
    //    attribute changes regardless of how the dialog opened.
    this.observer = new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.type !== "attributes") continue
        if (m.attributeName !== "open") continue
        const target = m.target
        if (!(target instanceof HTMLDialogElement)) continue
        const wasOpen = m.oldValue !== null
        const isOpen = target.hasAttribute("open")
        if (isOpen && !wasOpen) this.increment()
        else if (!isOpen && wasOpen) this.decrement()
      }
    })
    this.observer.observe(document.body, {
      attributes: true,
      subtree: true,
      attributeFilter: ["open"],
      attributeOldValue: true,
    })

    // 2) Document-level `close` listener (capture phase — the native
    //    `close` event does NOT bubble). Acts as a redundancy net in
    //    case the mutation observer misses an attribute flip (e.g.
    //    Turbo morph swapping the dialog DOM mid-close). The
    //    `reconcile()` call recounts open dialogs from scratch so
    //    spurious increments / decrements self-heal.
    this.onClose = () => this.reconcile()
    document.addEventListener("close", this.onClose, true)

    // 3) Initial reconcile — pick up any `<dialog open>` already in
    //    the DOM at mount time (e.g. the TOTP enrollment modal which
    //    auto-opens on /settings, or a server-rendered open dialog).
    this.reconcile()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
    if (this.onClose) {
      document.removeEventListener("close", this.onClose, true)
      this.onClose = null
    }
    // Restore page scroll on teardown — defensive, in case the body
    // controller is ever re-mounted with a stale lock attribute.
    delete document.body.dataset.modalOpen
    this.openCount = 0
  }

  increment() {
    this.openCount += 1
    if (this.openCount === 1) {
      document.body.dataset.modalOpen = "yes"
    }
  }

  decrement() {
    this.openCount = Math.max(0, this.openCount - 1)
    if (this.openCount === 0) {
      delete document.body.dataset.modalOpen
    }
  }

  // Recount open dialogs from the live DOM. Used on `close` events
  // (redundancy net) and at connect time (initial sync). Keeps the
  // counter honest even if a mutation slipped through.
  reconcile() {
    const openDialogs = document.querySelectorAll("dialog[open]")
    const next = openDialogs.length
    if (next === this.openCount) return
    this.openCount = next
    if (next === 0) {
      delete document.body.dataset.modalOpen
    } else {
      document.body.dataset.modalOpen = "yes"
    }
  }
}
