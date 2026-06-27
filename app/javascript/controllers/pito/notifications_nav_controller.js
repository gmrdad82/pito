// pito--notifications-nav
//
// Mounted on the notifications list injected into #pito-sidebar by ctrl+/.
// Keyboard:
//   ↑ / ↓   — move the highlight through notification rows. Landing on an
//             UNREAD row marks it READ on arrival (optimistic DOM update +
//             PATCH /notifications/:id { read: true }). Already-read rows are
//             left untouched — arrow movement never flips read → unread.
//   Escape  — handled by pito--resume (clears the sidebar)
// Mouse:
//   click a row — toggle its read/unread state (optimistic DOM update + PATCH).
//                 Clicking is the only way to flip a row back to unread.
//
// The list order is NEVER re-sorted client-side: read/unread state changes
// update IN PLACE so rows never jump under the cursor. The unread-first order
// is applied server-side (Notification.panel_ordered) when a fresh sidebar is
// rendered on open/broadcast.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { paletteOpen } from "pito/settings"

const HIGHLIGHT = "pito-resume-highlight"

export default class extends Controller {
  connect() {
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onKey.bind(this), { signal: this.abort.signal })
    this.element.addEventListener("click", this.#onClick.bind(this), { signal: this.abort.signal })
    this.index = -1
    const rows = this.#rows()
    if (rows.length) {
      this.index = 0
      this.#paint(rows)
    }
  }

  disconnect() {
    this.abort?.abort()
  }

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-notification-row"))
  }

  #onKey(e) {
    if (paletteOpen()) return // command palette owns the keys while open

    const rows = this.#rows()
    if (!rows.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.#move(rows, 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.#move(rows, -1)
    }
  }

  #onClick(e) {
    const row = e.target.closest(".pito-notification-row")
    if (!row) return
    const rows = this.#rows()
    this.index = rows.indexOf(row)
    this.#paint(rows)
    this.#toggle(row)
  }

  #move(rows, delta) {
    // ↓ while already on the last row → ask the generic pager to load more
    // (it no-ops if there is no next page). The appended rows join #rows() on
    // the next keypress, so the highlight can keep descending into them.
    if (delta > 0 && this.index === rows.length - 1) {
      this.element.dispatchEvent(new CustomEvent("pito:list-pager:more"))
    }

    if (this.index === -1) {
      this.index = delta > 0 ? 0 : rows.length - 1
    } else {
      this.index = Math.max(0, Math.min(rows.length - 1, this.index + delta))
    }
    this.#paint(rows)
    rows[this.index]?.scrollIntoView({ block: "nearest" })
    this.#markReadOnArrival(rows[this.index])
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT, i === this.index))
  }

  // Arrow-onto-unread: mark READ on arrival (once). Never flips read → unread —
  // already-read rows are left untouched.
  #markReadOnArrival(row) {
    if (!row) return
    if (row.dataset.read === "true") return
    this.#applyReadState(row, true)
    this.#persist(row.dataset.notificationId, true)
  }

  // Click: toggle read ↔ unread. Updates the row IN PLACE (no re-sort) so the
  // list keeps its current order and rows never jump under the cursor.
  #toggle(row) {
    if (!row) return
    const nowRead = row.dataset.read !== "true" // flip current state
    this.#applyReadState(row, nowRead)
    this.#persist(row.dataset.notificationId, nowRead)
  }

  // Update a row's read/unread VISUAL indicator in place: data-read attribute,
  // dot glyph + colour, and the message emphasis.
  #applyReadState(row, read) {
    row.dataset.read = String(read)

    const dot = row.querySelector(".pito-notification-dot")
    if (dot) {
      dot.textContent = read ? "○" : "●"
      dot.classList.toggle("text-cyan", !read)
      dot.classList.toggle("text-fg-faded", read)
    }

    const msg = row.querySelector(".pito-notification-message")
    if (msg) {
      msg.classList.toggle("text-fg", !read)
      msg.classList.toggle("font-bold", !read)
      msg.classList.toggle("text-fg-dim", read)
    }
  }

  #persist(id, read) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(`/notifications/${id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(csrf ? { "X-CSRF-Token": csrf } : {}),
      },
      body: JSON.stringify({ read }),
    }).catch((err) => console.warn("[pito--notifications-nav] persist failed:", err))
  }
}
