// pito--resume
//
// Mounted on #pito-sidebar. When /resume populates the sidebar via a Turbo Stream
// update, this controller activates keyboard and mouse navigation for the
// conversation list.
//
// Keyboard:
//   ↑ / ↓   — move highlight through rows
//   Enter   — select highlighted row
//   Escape  — clear (empty) the sidebar
//   dd      — vim-style delete: press d to arm the highlighted row (shows confirm
//             prompt), then press d again within ~500ms to delete via DELETE /chat/<uuid>.
//             The armed state auto-disarms after 500ms if no second d arrives.
//             Moving the highlight or pressing Escape also disarms.
//             Ignored while an input/rename field has focus.
//
// Mouse:
//   click .pito-conversation-row — select that row
//
// Touch (mobile only, <768px + pointer:coarse — Z22):
//   swipe a row LEFT past the threshold → it snaps open, revealing a red Delete
//   button at the right edge; TAP that button to delete (reuses #deleteConversation).
//   The swipe only REVEALS — deletion always needs the explicit tap. Only one
//   row open at a time; a mostly-vertical drag is ignored so the list scrolls.
//
// Selecting a row:
//   - If the row has class "is-current" (already the active conversation) → just clear.
//   - Otherwise → Turbo.visit("/chat/<uuid>").
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { paletteOpen } from "pito/settings"
import { Turbo } from "@hotwired/turbo-rails"

const HIGHLIGHT_CLASS = "pito-resume-highlight"
// Per-browser UI state: which sidebar panel (if any) is open, so a reload
// restores it. Ephemeral view state → localStorage, not the server.
const SIDEBAR_KEY = "pito:sidebar"

// ── Mobile swipe-to-delete (Z22) ──────────────────────────────────────────────
// Reveal distance the row slides left to expose the Delete button — MUST match
// `--pito-swipe-reveal` in application.css.
const SWIPE_REVEAL = 96
// Past this leftward drag the row snaps open on release; below it snaps closed.
const SWIPE_THRESHOLD = SWIPE_REVEAL / 2
// Minimum movement before we lock the gesture axis / count it as a real drag.
const SWIPE_AXIS_LOCK = 8

export default class extends Controller {
  #dismissHandler = null
  #armTimer = null
  // Swipe state
  #swipeRow = null      // row under an active touch gesture
  #openRow = null       // row currently snapped open (only one at a time)
  #swipeStartX = 0
  #swipeStartY = 0
  #swipeDx = 0
  #swipeAxis = null     // null | "h" | "v"
  #suppressClick = false
  #wasOpen = false      // whether the sidebar panel (an <aside>) was present

  connect() {
    this.abort = new AbortController()
    document.addEventListener("keydown", this.#onKey.bind(this), { signal: this.abort.signal })
    // Mobile swipe-to-delete: delegated touch handlers survive row replacement.
    // touchmove is passive:false so a horizontal drag can preventDefault the
    // list scroll once the gesture is locked to the horizontal axis.
    this.element.addEventListener("touchstart", this.#onTouchStart.bind(this), { signal: this.abort.signal })
    this.element.addEventListener("touchmove", this.#onTouchMove.bind(this), { passive: false, signal: this.abort.signal })
    this.element.addEventListener("touchend", this.#onTouchEnd.bind(this), { signal: this.abort.signal })
    this.element.addEventListener("touchcancel", this.#onTouchEnd.bind(this), { signal: this.abort.signal })
    // Sequential Esc: capture-phase so it runs BEFORE the chatbox's suggestions
    // Esc. When the sidebar is open it closes the sidebar and swallows the event
    // (so a /command palette underneath survives); the next Esc reaches the
    // palette. Also makes Esc close the notifications panel (which has no
    // conversation rows and so isn't handled by #onKey).
    document.addEventListener("keydown", this.#onEscapeCapture.bind(this), { capture: true, signal: this.abort.signal })
    this.element.addEventListener("click", this.#onClick.bind(this), { signal: this.abort.signal })
    this.highlightIndex = -1
    this.armedRow = null

    // Allow other controllers (home-transition, command-palette) to dismiss the
    // sidebar without holding a reference to this controller.
    this.#dismissHandler = () => this.dismiss()
    window.addEventListener("pito:resume:dismiss", this.#dismissHandler)

    // Desktop overlay backdrop: clicking the scrim dismisses the sidebar. The
    // AbortController signal cleans up the listener automatically on disconnect.
    const backdrop = document.getElementById("pito-sidebar-backdrop")
    if (backdrop) {
      backdrop.addEventListener("click", () => this.dismiss(), { signal: this.abort.signal })
    }

    // The sidebar content is injected via a Turbo Stream UPDATE (this controller
    // stays connected). Watch for it: on the open transition we (a) blur the
    // chatbox and clear the command comet (pito:comet-clear — a sidebar command
    // produces no backend message) and (b) highlight the first row so arrow-nav
    // is immediately visible.
    // subtree:true so a row REPLACE (e.g. after rename) re-pins the highlight to
    // the same position instead of losing it.
    this.observer = new MutationObserver(() => this.#onContentChange())
    this.observer.observe(this.element, { childList: true, subtree: true })

    // Restore a previously-open panel after reload.
    this.#restore()
  }

  disconnect() {
    this.abort?.abort()
    this.observer?.disconnect()
    window.removeEventListener("pito:resume:dismiss", this.#dismissHandler)
  }

  // Public: allows other controllers to dismiss the sidebar without a direct
  // reference. Called by the pito:resume:dismiss window event and can also be
  // invoked programmatically (e.g. from tests or sibling controllers).
  dismiss() {
    this.#clear()
  }

  // Re-open the panel that was open before reload. Skips if the sidebar is
  // already populated (e.g. a Turbo navigation kept it).
  #restore() {
    // The start screen + dynamic 404 NEVER show a sidebar (both render the
    // StartScreen component, marked by pito--home-transition, which also
    // dispatches pito:resume:dismiss on connect). Don't restore it from
    // localStorage here — that would re-open it after a delete-last-conversation.
    if (document.querySelector('[data-controller~="pito--home-transition"]')) return
    if (this.element.innerHTML.trim()) return
    const want = localStorage.getItem(SIDEBAR_KEY)
    if (!want) return

    let url
    if (want === "notifications") {
      url = "/notifications"
    } else if (want === "conversations") {
      const m = location.pathname.match(/\/chat\/([0-9a-f-]+)/i)
      url = "/resume" + (m ? `?uuid=${m[1]}` : "")
    } else {
      return
    }

    fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      .then((r) => (r.ok ? r.text() : null))
      .then((html) => { if (html) Turbo.renderStreamMessage(html) })
      .catch(() => {})
  }

  #onContentChange() {
    // When the sidebar gains content, drop key-focus from the chatbox so its
    // keystrokes drive the sidebar (or the sidebar's own input, e.g. IGDB search).
    // Dismiss with `m` (→ refocuses the chatbox) or Esc (→ leaves focus alone).
    const open = !!this.element.querySelector("aside")
    if (open) this.#blurChatbox()

    // Z24: on mobile the panel is a fixed full-width overlay; anchor its scroll
    // body at the top so the header + first rows are visible on open instead of
    // landing below the fold. Reset only on the open transition (not on every
    // row replace, e.g. a rename) so an in-place edit doesn't jump to the top.
    if (open && !this.#wasOpen) {
      const scroller = this.element.querySelector(".pito-scroll-fade-slim")
      if (scroller) scroller.scrollTop = 0

      // J23: a sidebar/client-only command (/resume, /themes, the pickers, IGDB
      // import) opens this panel but produces NO echo and NO scrollback result,
      // so the comet (pito--dots) — shown on every pito:submitted — would hang.
      // Clear it the moment the panel opens. This is the reliable hide path:
      // every sidebar partial injects an <aside> here, and the MutationObserver
      // fires after it lands (unlike the racy _done_signal append).
      document.dispatchEvent(new CustomEvent("pito:comet-clear", { bubbles: true }))
    }
    this.#wasOpen = open

    const rows = this.#rows()

    // Persist which panel is open so a reload can restore it.
    if (rows.length) {
      localStorage.setItem(SIDEBAR_KEY, "conversations")
    } else if (this.element.querySelector(".pito-notification-row")) {
      localStorage.setItem(SIDEBAR_KEY, "notifications")
    }

    if (!rows.length) {
      this.highlightIndex = -1
      return
    }

    if (this.highlightIndex === -1) {
      // Sidebar just opened — highlight the first row. (The comet is cleared on
      // the open transition above via pito:comet-clear.)
      this.highlightIndex = 0
    } else {
      // Content changed (e.g. a row was renamed → Turbo-replaced) — keep the
      // highlight pinned to the same position so it stays selected.
      this.highlightIndex = Math.min(this.highlightIndex, rows.length - 1)
    }
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
  }

  // Called by Turbo after the sidebar content is updated so we can initialise
  // the highlight. Turbo fires turbo:render which we listen to globally, but
  // it is simpler to rely on the MutationObserver-based connect/disconnect
  // lifecycle. When the element's children change (Turbo Stream update) the
  // controller is not re-connected, so we re-initialise on every keydown.

  // ── Private ────────────────────────────────────────────────────────────────

  #rows() {
    return Array.from(this.element.querySelectorAll(".pito-conversation-row"))
  }

  // Drop focus from the chatbox (only if it currently holds it) so the sidebar
  // owns the keyboard while it's open.
  #blurChatbox() {
    const chatbox = document.querySelector('[data-pito--chat-form-target="inputField"]')
    if (chatbox && document.activeElement === chatbox) chatbox.blur()
  }

  #onEscapeCapture(e) {
    if (e.key !== "Escape") return
    // When a row is armed, let the bubbling #onKey handler disarm it instead —
    // we don't swallow the event here so #onKey can decide.
    if (this.armedRow) return
    if (!this.element.innerHTML.trim()) return // nothing open — let it pass through
    e.preventDefault()
    e.stopImmediatePropagation()
    this.#clear()
  }

  #onKey(e) {
    if (paletteOpen()) return // command palette owns the keys while open

    const rows = this.#rows()
    if (!rows.length) return

    if (e.key === "ArrowDown") {
      e.preventDefault()
      this.#disarm()
      this.#move(rows, 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      this.#disarm()
      this.#move(rows, -1)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const highlighted = rows[this.highlightIndex]
      if (highlighted) this.#select(highlighted)
    } else if (e.key === "Escape") {
      e.preventDefault()
      if (this.armedRow) {
        this.#disarm()
      } else {
        this.#clear()
      }
    } else if (e.key === "d") {
      // J22: ignore `d` only while a SIDEBAR-owned input has focus (the inline
      // rename field) so it types normally there. A focused chatbox must NOT
      // swallow the delete — drop its focus (no-op when it isn't focused) and
      // proceed; the preventDefault below stops `d` from being typed there, so
      // `d`/`dd` always drive the sidebar instead of the chatbox.
      const active = document.activeElement
      if (active?.matches("input, textarea, [contenteditable]") && this.element.contains(active)) return
      this.#blurChatbox()
      const highlighted = rows[this.highlightIndex]
      if (!highlighted) return
      e.preventDefault()
      if (this.armedRow === highlighted) {
        // Second d within the 500ms window — confirm delete
        this.#deleteConversation(highlighted)
      } else {
        // First d — arm the row; auto-disarm after 500ms if no second d arrives
        this.#disarm()
        this.#arm(highlighted)
      }
    } else if (e.key === "n") {
      // Inline-rename the highlighted conversation. The pito--rename controller
      // on that row listens for this event and swaps the name for an <input>.
      const highlighted = rows[this.highlightIndex]
      if (highlighted) {
        e.preventDefault()
        highlighted.dispatchEvent(new CustomEvent("pito:rename:start"))
      }
    }
  }

  #onClick(e) {
    // Tap on the revealed (swiped-open) Delete button → delete this row. Reuses
    // the same DELETE path as the desktop `dd` flow.
    const deleteBtn = e.target.closest("[data-conversation-delete]")
    if (deleteBtn) {
      e.preventDefault()
      e.stopPropagation()
      const target = deleteBtn.closest(".pito-conversation-row")
      if (target) this.#deleteConversation(target)
      return
    }

    // Swallow the click that fires right after a real horizontal swipe so the
    // gesture never doubles as a navigation tap.
    if (this.#suppressClick) {
      this.#suppressClick = false
      return
    }

    // While a row is swiped open, any tap just closes it (no navigation).
    if (this.#openRow) {
      this.#closeSwipe(this.#openRow)
      if (e.target.closest(".pito-conversation-row")) return
    }

    const row = e.target.closest(".pito-conversation-row")
    if (!row) return
    // Click == arrow-to-it + Enter: pin the highlight to this row, then select it.
    const rows = this.#rows()
    const idx  = rows.indexOf(row)
    if (idx !== -1) {
      this.#disarm()
      this.highlightIndex = idx
      rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
    }
    this.#select(row)
  }

  #move(rows, delta) {
    // Initialise to first/last on first keypress
    if (this.highlightIndex === -1) {
      this.highlightIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      this.highlightIndex = Math.max(0, Math.min(rows.length - 1, this.highlightIndex + delta))
    }
    rows.forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLASS, i === this.highlightIndex))
    rows[this.highlightIndex]?.scrollIntoView({ block: "nearest" })
  }

  #select(row) {
    const uuid = row.dataset.conversationUuid
    if (!uuid) { this.#clear(); return }

    if (row.classList.contains("is-current")) {
      // Already on this conversation — just close the sidebar.
      this.#clear()
      return
    }

    this.#clear()
    Turbo.visit("/chat/" + uuid)
  }

  #clear() {
    this.#disarm()
    this.element.innerHTML = ""
    this.highlightIndex = -1
    this.#openRow = null
    this.#swipeRow = null
    this.#wasOpen = false
    // Forget the persisted panel so a reload doesn't re-open a dismissed sidebar.
    localStorage.removeItem(SIDEBAR_KEY)
  }

  // ── Mobile swipe-to-delete (Z22) ─────────────────────────────────────────────
  // Touch a row, drag left past SWIPE_THRESHOLD, release → the row snaps open
  // revealing the Delete button (tap it via #onClick to delete). Below the
  // threshold (or a mostly-vertical drag) it snaps closed and list scrolling is
  // left untouched. Only one row open at a time.

  // True only on a touch + narrow viewport (matches the CSS gesture guard). On a
  // desktop pointer the gesture is inert and `dd` remains the delete path.
  #swipeEnabled() {
    return window.matchMedia?.("(max-width: 767px) and (pointer: coarse)").matches ?? false
  }

  #content(row) {
    return row?.querySelector(".pito-conversation-row__content")
  }

  #onTouchStart(e) {
    if (!this.#swipeEnabled()) return
    const row = e.target.closest(".pito-conversation-row")
    // Tapping outside the open row (or on a different row) closes it.
    if (this.#openRow && this.#openRow !== row) this.#closeSwipe(this.#openRow)
    if (!row) return
    // Touches that start on the Delete button are taps → handled by #onClick.
    if (e.target.closest("[data-conversation-delete]")) return

    const t = e.touches[0]
    this.#swipeRow = row
    this.#swipeStartX = t.clientX
    this.#swipeStartY = t.clientY
    this.#swipeDx = 0
    this.#swipeAxis = null
  }

  #onTouchMove(e) {
    if (!this.#swipeRow) return
    const t = e.touches[0]
    const dx = t.clientX - this.#swipeStartX
    const dy = t.clientY - this.#swipeStartY

    // Lock the axis once movement is meaningful. A mostly-vertical drag releases
    // the row so the list scrolls normally; horizontal begins the swipe.
    if (this.#swipeAxis === null) {
      if (Math.abs(dx) < SWIPE_AXIS_LOCK && Math.abs(dy) < SWIPE_AXIS_LOCK) return
      this.#swipeAxis = Math.abs(dx) > Math.abs(dy) ? "h" : "v"
      if (this.#swipeAxis === "v") { this.#swipeRow = null; return }
      this.#swipeRow.classList.add("pito-row-swiping")
    }
    if (this.#swipeAxis !== "h") return

    e.preventDefault() // own the horizontal axis; block list scroll mid-drag
    const base = this.#openRow === this.#swipeRow ? -SWIPE_REVEAL : 0
    const x = Math.max(-SWIPE_REVEAL, Math.min(0, base + dx))
    this.#swipeDx = x
    const content = this.#content(this.#swipeRow)
    if (content) content.style.transform = `translateX(${x}px)`
  }

  #onTouchEnd() {
    const row = this.#swipeRow
    this.#swipeRow = null
    if (!row || this.#swipeAxis !== "h") return

    row.classList.remove("pito-row-swiping")
    const content = this.#content(row)
    if (content) content.style.transform = "" // hand the resting position to CSS

    if (this.#swipeDx <= -SWIPE_THRESHOLD) {
      this.#openSwipe(row)
    } else {
      this.#closeSwipe(row)
    }
    // A real horizontal drag happened — swallow the click it would synthesize.
    this.#suppressClick = Math.abs(this.#swipeDx) >= SWIPE_AXIS_LOCK
  }

  #openSwipe(row) {
    if (this.#openRow && this.#openRow !== row) this.#closeSwipe(this.#openRow)
    row.classList.add("pito-row-swipe-open")
    this.#openRow = row
  }

  #closeSwipe(row) {
    if (!row) return
    row.classList.remove("pito-row-swipe-open")
    const content = this.#content(row)
    if (content) content.style.transform = ""
    if (this.#openRow === row) this.#openRow = null
  }

  // Arms a row for deletion: saves its original inner HTML and replaces the
  // visible content with a confirm prompt. Starts a 500ms auto-disarm timer so
  // a lone `d` that isn't followed by a second `d` in time cleans itself up.
  // Only one row is armed at a time.
  #arm(row) {
    this.armedRow = row
    row._resumeSavedHtml = row.innerHTML
    // Witty confirm copy injected server-side (Pito::Copy); orange = confirmation,
    // 16px (no size class — the app is 16px-only), italic.
    const prompt = this.element.querySelector("[data-delete-prompt]")?.dataset.deletePrompt
                   || "press d again to delete"
    row.innerHTML = `<span class="text-orange italic px-1">${prompt}</span>`
    clearTimeout(this.#armTimer)
    this.#armTimer = setTimeout(() => this.#disarm(), 500)
  }

  // Disarms any currently armed row, restoring its original HTML, and cancels
  // the auto-disarm timer.
  #disarm() {
    clearTimeout(this.#armTimer)
    this.#armTimer = null
    if (!this.armedRow) return
    if (this.armedRow._resumeSavedHtml !== undefined) {
      this.armedRow.innerHTML = this.armedRow._resumeSavedHtml
      delete this.armedRow._resumeSavedHtml
    }
    this.armedRow = null
  }

  // Sends DELETE /chat/<uuid> (async delete). The server marks the conversation
  // deleting and broadcasts the row → shimmering-dots over pito:global, then
  // removes it when DeleteConversationJob finishes — so we don't touch the row
  // here, except to leave it if it's the currently-open conversation.
  #deleteConversation(row) {
    const uuid = row.dataset.conversationUuid
    if (!uuid) return

    const csrfToken = document.querySelector("meta[name=csrf-token]")?.content
    const headers = { "X-CSRF-Token": csrfToken || "" }

    // Determine the current conversation uuid from the hidden input on the chat page.
    const currentUuidInput = document.querySelector("input[name=uuid]")
    const currentUuid = currentUuidInput?.value

    fetch(`/chat/${uuid}`, { method: "DELETE", headers })
      .then((r) => {
        if (!r.ok) return
        // Leave the conversation if it's the one open; otherwise the pito:global
        // broadcast turns the row into shimmering dots and later removes it.
        if (currentUuid && uuid === currentUuid) window.location.href = "/"
      })
      .catch(() => {})

    // Clear armed state and timer immediately (row will be removed or page will navigate).
    clearTimeout(this.#armTimer)
    this.#armTimer = null
    this.armedRow = null
  }
}
