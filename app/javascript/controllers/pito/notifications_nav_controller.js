// pito--notifications-nav
//
// Mounted on the notifications list injected into #pito-sidebar by ctrl+/.
// Keyboard:
//   ↑ / ↓   — move the highlight through notification rows
//   Space   — toggle read/unread on the highlighted row (optimistic DOM update
//             + PATCH /notifications/:id { read: <bool> })
//   Escape  — handled by pito--resume (clears the sidebar)
// Mouse:
//   click a row — highlight it
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
    } else if (e.key === " " || e.key === "Spacebar") {
      e.preventDefault()
      this.#toggle(rows[this.index])
    }
  }

  #onClick(e) {
    const row = e.target.closest(".pito-notification-row")
    if (!row) return
    this.index = this.#rows().indexOf(row)
    this.#paint(this.#rows())
  }

  #move(rows, delta) {
    if (this.index === -1) {
      this.index = delta > 0 ? 0 : rows.length - 1
    } else {
      this.index = Math.max(0, Math.min(rows.length - 1, this.index + delta))
    }
    this.#paint(rows)
    rows[this.index]?.scrollIntoView({ block: "nearest" })
  }

  #paint(rows) {
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT, i === this.index))
  }

  #toggle(row) {
    if (!row) return
    const id = row.dataset.notificationId
    const nowRead = row.dataset.read !== "true" // flip current state
    row.dataset.read = String(nowRead)

    const dot = row.querySelector(".pito-notification-dot")
    if (dot) {
      dot.textContent = nowRead ? "○" : "●"
      dot.classList.toggle("text-cyan", !nowRead)
      dot.classList.toggle("text-fg-faded", nowRead)
    }

    const msg = row.querySelector(".pito-notification-message")
    if (msg) {
      msg.classList.toggle("text-fg", !nowRead)
      msg.classList.toggle("font-bold", !nowRead)
      msg.classList.toggle("text-fg-dim", nowRead)
    }

    // Re-sort DOM rows: unread first, then read — each group newest-first.
    // Keep this.index at the same slot so the cursor lands on whatever row
    // is now at that position (the next item), rather than jumping to top.
    const sorted = this.#resortRows()
    this.index = Math.min(this.index, sorted.length - 1)
    this.#paint(sorted)

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(`/notifications/${id}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        ...(csrf ? { "X-CSRF-Token": csrf } : {}),
      },
      body: JSON.stringify({ read: nowRead }),
    }).catch((err) => console.warn("[pito--notifications-nav] toggle failed:", err))
  }

  // Re-sort .pito-notification-row elements inside this.element by:
  //   1. unread rows first (data-read !== "true")
  //   2. then read rows
  //   3. within each group: newest first (data-created-at desc, unix epoch)
  // Returns the sorted rows array after re-appending them to the DOM.
  #resortRows() {
    const rows = this.#rows()
    const sorted = [...rows].sort((a, b) => {
      const aUnread = a.dataset.read !== "true" ? 1 : 0
      const bUnread = b.dataset.read !== "true" ? 1 : 0
      if (aUnread !== bUnread) return bUnread - aUnread  // unread (1) before read (0)
      const aTs = parseInt(a.dataset.createdAt || "0", 10)
      const bTs = parseInt(b.dataset.createdAt || "0", 10)
      return bTs - aTs  // newest first within each group
    })
    sorted.forEach(row => this.element.appendChild(row))
    return sorted
  }
}
