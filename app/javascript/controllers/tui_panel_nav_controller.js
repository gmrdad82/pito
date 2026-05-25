import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-panel-nav"
//
// Purpose:
//   Provides TAB / Shift-TAB linear panel navigation across all pito
//   screens and emits the canonical `pito:panel:focused` document event
//   whenever the active panel changes.
//
// Architecture:
//   This controller is the NAMED owner of TAB-based panel traversal.
//   The `tui-cursor` controller (also mounted on <body>) currently shares
//   the same Tab/Shift-Tab handling as part of its broader cursor model.
//   To avoid double-handling, this controller uses a cooperative guard:
//   when `tui-cursor` is already present on the same element (or body),
//   it defers its own keydown handler and only performs the
//   `pito:panel:focused` bridge (forwarding `tui:panel-focus-changed`
//   with the public event name). If `tui-cursor` is absent, this
//   controller provides the full Tab-to-panel navigation standalone.
//
// Panel detection:
//   A "panel" is any element with `data-tui-cursor-target="panel"`.
//   This mirrors the contract used by `tui-cursor` so both controllers
//   share the same DOM hook without coordination overhead.
//
// Key bindings:
//   Tab        — focus next panel in document order (wraps).
//   Shift-Tab  — focus previous panel in document order (wraps).
//
// Guards — Tab is NOT intercepted when:
//   - Focus is inside a form input, textarea, select, or [contenteditable].
//   - A `<dialog>` is open (dialog owns its own focus trap).
//   - The `:` command palette overlay is open (palette intercepts Tab for
//     suggestion cycling; detected via the palette's `[hidden]` attribute
//     — absent = open).
//   - `tui-cursor` is active on <body> (cursor owns Tab; this controller
//     defers to it and only provides the event bridge).
//
// Auto-scroll behavior:
//   After moving focus to a panel, the controller checks whether the panel
//   is fully visible within its nearest scrollable ancestor. If it is not
//   fully visible, `scrollIntoView({ behavior: "smooth", block: "nearest" })`
//   is called to bring the panel into view without disturbing panels that
//   are already on-screen. The scroll is skipped when the panel is 100%
//   within the scroll container's client rect — this prevents spurious
//   smooth-scroll jank on panels already visible to the user.
//
//   Scroll container resolution: `nearestScrollContainer(el)` walks the DOM
//   ancestor chain from the panel element upward, checking each element's
//   computed `overflow-y` (and `overflow`) for `auto` or `scroll`. Falls
//   back to `document.documentElement` when no scrollable ancestor is found.
//   This means the check works regardless of whether the scroll container
//   is `<main>`, a `.home-grid` wrapper, or the document root — it adapts
//   to the actual layout without hardcoding a selector.
//
// Events emitted:
//   `pito:panel:focused` (document, bubbles: false)
//     detail: { panelId: string | null, panelTitle: string | null }
//     Fired on every panel focus change. Consumers must not make
//     assumptions about the presence of either detail field — both may
//     be null when the focused panel has no `id` / no `data-panel-title`.
//
// Related:
//   tui_cursor_controller.js     — cursor model + mode state machine
//   tui_breadcrumb_controller.js — consumes `tui:panel-focus-changed`
//   tui_panel_cable_controller.js — emits `pito:panel:<name>:*` cable events
//
// Focusables:
//   None — this controller does not manage a focusable list.
//
// Cable subscriptions:
//   None.

const INPUT_SELECTOR =
  'input[type="text"], input[type="url"], input[type="email"], ' +
  'input[type="password"], input[type="number"], input[type="search"], ' +
  'input[type="tel"], input:not([type]), textarea, ' +
  '[contenteditable=""], [contenteditable="true"], select'

// Returns the nearest ancestor element (including el itself) whose
// computed overflow-y (or overflow shorthand) is "auto" or "scroll",
// indicating it is the actual scroll container for el. Falls back to
// document.documentElement when no scrollable ancestor exists.
function nearestScrollContainer(el) {
  let node = el.parentElement
  while (node && node !== document.documentElement) {
    const style = window.getComputedStyle(node)
    const overflowY = style.overflowY || style.overflow
    if (overflowY === "auto" || overflowY === "scroll") return node
    node = node.parentElement
  }
  return document.documentElement
}

// Returns true when el is fully visible (no part clipped) within the
// bounds of its nearest scroll container. Uses getBoundingClientRect on
// both the element and the container so the check is in viewport-space
// coordinates and works regardless of nested transforms.
function isPanelFullyVisible(el) {
  const container = nearestScrollContainer(el)
  const elRect = el.getBoundingClientRect()
  const cRect = container === document.documentElement
    ? { top: 0, left: 0, bottom: window.innerHeight, right: window.innerWidth }
    : container.getBoundingClientRect()
  return (
    elRect.top >= cRect.top &&
    elRect.bottom <= cRect.bottom &&
    elRect.left >= cRect.left &&
    elRect.right <= cRect.right
  )
}

// Scrolls el into view only when it is not already fully visible in its
// scroll container. Skips the call entirely when the panel is on-screen
// to avoid spurious smooth-scroll jitter for the common case.
function scrollPanelIntoViewIfNeeded(el) {
  if (!isPanelFullyVisible(el)) {
    el.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }
}

export default class extends Controller {
  connect() {
    this.boundKey = this.handleKey.bind(this)
    this.boundFocusChanged = this.handleFocusChanged.bind(this)

    document.addEventListener("keydown", this.boundKey, true)
    document.addEventListener("tui:panel-focus-changed", this.boundFocusChanged)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey, true)
    document.removeEventListener("tui:panel-focus-changed", this.boundFocusChanged)
  }

  // Bridge: re-emit `tui:panel-focus-changed` as the public
  // `pito:panel:focused` event so downstream consumers subscribe to
  // the stable public name rather than the cursor controller's internal
  // event name. The internal event carries { panel, subPanel, title };
  // the public event forwards panelId (from the focused element's id
  // attribute, if any) and panelTitle (from detail.panel).
  //
  // Also auto-scrolls the newly focused panel into view when it is not
  // fully visible in its scroll container — the tui-cursor controller owns
  // focus traversal in this path but does not perform page-level scroll.
  handleFocusChanged(event) {
    const detail = event.detail || {}

    // Scroll the focused panel element into view if it's off-screen.
    const focusedEl = document.querySelector(
      '[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]'
    )
    if (focusedEl) scrollPanelIntoViewIfNeeded(focusedEl)

    document.dispatchEvent(
      new CustomEvent("pito:panel:focused", {
        bubbles: false,
        detail: {
          panelId: this.focusedPanelId(),
          panelTitle: detail.panel ?? null
        }
      })
    )
  }

  // Returns the id of the currently focused panel element (the one
  // carrying `data-tui-cursor-focused="yes"`), or null when absent.
  focusedPanelId() {
    const el = document.querySelector(
      '[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]'
    )
    return el ? (el.id || null) : null
  }

  handleKey(event) {
    if (event.key !== "Tab") return

    // Cooperative guard: when tui-cursor is mounted on <body>, it owns
    // Tab. Let it handle panel traversal; we only provide the event bridge.
    if (this.tuiCursorActive()) return

    // Skip when a <dialog> is open (dialog owns its own focus trap).
    if (document.querySelector("dialog[open]")) return

    // Skip when the command palette is open (palette cycles suggestions
    // via Tab). The palette element carries [hidden] when closed; absent
    // = open.
    const palette = document.querySelector("[data-controller~='tui-command-palette']")
    if (palette && !palette.hasAttribute("hidden")) return

    // Skip when focus is on a text input or select — browser handles.
    const active = document.activeElement
    if (active && active.matches && active.matches(INPUT_SELECTOR)) return

    // Skip modifiers other than Shift.
    if (event.ctrlKey || event.metaKey || event.altKey) return

    event.preventDefault()
    event.stopPropagation()

    const panels = Array.from(
      document.querySelectorAll('[data-tui-cursor-target="panel"]')
    )
    if (panels.length === 0) return

    const focused = document.querySelector(
      '[data-tui-cursor-target="panel"][data-tui-cursor-focused="yes"]'
    )
    const currentIdx = focused ? panels.indexOf(focused) : -1

    let nextIdx
    if (event.shiftKey) {
      nextIdx =
        currentIdx <= 0
          ? panels.length - 1
          : currentIdx - 1
    } else {
      nextIdx =
        currentIdx < 0 || currentIdx >= panels.length - 1
          ? 0
          : currentIdx + 1
    }

    // Clear current focus marker.
    panels.forEach((p) => {
      p.removeAttribute("data-tui-cursor-focused")
    })

    const next = panels[nextIdx]
    if (next) {
      next.setAttribute("data-tui-cursor-focused", "yes")
      scrollPanelIntoViewIfNeeded(next)

      // Emit pito:panel:focused directly — the cursor controller is not
      // present in this standalone path, so we emit ourselves.
      document.dispatchEvent(
        new CustomEvent("pito:panel:focused", {
          bubbles: false,
          detail: {
            panelId: next.id || null,
            panelTitle: next.dataset.panelTitle ?? null
          }
        })
      )
    }
  }

  // Detect whether tui-cursor is active on the document body. Uses the
  // data-controller attribute presence rather than a Stimulus Application
  // lookup so it works without coupling to the Application instance.
  tuiCursorActive() {
    const body = document.body
    if (!body) return false
    const controllers = body.getAttribute("data-controller") || ""
    return controllers.split(/\s+/).includes("tui-cursor")
  }
}
