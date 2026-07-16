// pito--anchor-jump
//
// Cross-reference navigation: a search-hit row (Pito::Chat::Handlers::
// SearchConversations, rendered via Pito::Event::SystemComponent's data grid)
// stamps EVERY cell span of a hit row with data-anchor-event-id="<id>" — the
// event a "#N" reference resolves to. Clicking anywhere in such a row jumps
// the scrollback to the matching event (id="event_<id>"), mirroring the
// scroll_nav pills' Ctrl+Home smooth-scroll feel.
//
// Document-level delegation (same shape as pito--selection-scope: connect()
// binds to `document`, not `this.element`) because a hit row can render
// inside ANY system message, anywhere in the scrollback — there is no single
// container that owns every possible source. Mounted on #pito-scrollback
// alongside the other scrollback-wide behaviors (conversations/show).
//
// Cross-conversation hits: their anchor id has no matching event_<id> in
// THIS conversation's DOM (only the active conversation is rendered) — the
// lookup misses and the click is a graceful no-op.
//
// On-load jump: `/resume <uuid> <event_id>` (ChatController#handle_resume_uuid)
// navigates to `/chat/<uuid>#event_<id>` — the SAME `event_<id>` anchor a
// search-hit row carries. #connect checks location.hash for that shape and
// runs the identical scroll+flash via #jumpToEvent, so there is exactly ONE
// jump mechanism regardless of trigger (click vs fresh page load). A stale or
// cross-conversation event_id (not in this DOM) degrades to a no-op, same as
// a cross-conversation click.
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onClick = this.jump.bind(this)
    document.addEventListener("click", this.onClick)
    this.jumpFromHash()
  }

  disconnect() {
    document.removeEventListener("click", this.onClick)
  }

  jump(event) {
    const source = event.target.closest("[data-anchor-event-id]")
    if (!source) return

    this.jumpToEvent(source.dataset.anchorEventId)
  }

  // Reads `#event_<id>` off the current URL (set by the /resume <uuid>
  // <event_id> navigate) and performs the same jump. Graceful no-op when the
  // hash doesn't match the shape, or the id isn't in this DOM.
  jumpFromHash() {
    const match = window.location.hash.match(/^#event_(\d+)$/)
    if (!match) return

    this.jumpToEvent(match[1])
  }

  jumpToEvent(id) {
    const target = document.getElementById(`event_${id}`)
    if (!target) return // cross-conversation hit — no matching event in this DOM

    target.scrollIntoView({ behavior: "smooth", block: "start" })

    // Timeout lives on the TARGET, not the controller: two quick jumps to two
    // different messages must each clean up their own flash independently —
    // a controller-level timeout would cancel the first target's removal and
    // leave its highlight stuck on.
    target.classList.add("pito-anchor-flash")
    clearTimeout(target._pitoAnchorFlashTimeout)
    target._pitoAnchorFlashTimeout = setTimeout(() => target.classList.remove("pito-anchor-flash"), 2000)

    // Persistent marker: only ONE message carries it at a time, so drop it
    // from whichever element has it before moving it to the new target. No
    // timeout — it stays until the next jump moves it.
    document.querySelectorAll(".pito-anchor-highlight").forEach((el) => el.classList.remove("pito-anchor-highlight"))
    target.classList.add("pito-anchor-highlight")
  }
}
