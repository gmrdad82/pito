import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-cursor"
//
// =========================================================================
//  CONTRACT (locked 2026-05-21 for FB-165 — focus-list-per-panel rewrite)
//  Updated 2026-05-24: spatial Ctrl-hjkl panel nav dropped; TAB / Shift-TAB
//  are now the sole panel traversal keys (user decision 2026-05-23).
// =========================================================================
//
//  Vim-inspired NORMAL / INSERT modes + per-panel "focus list" cursor.
//
//  --- ARCHITECTURE: focus-list-per-panel ---
//
//  Every focusable element inside a panel/sub-panel carries
//
//    data-tui-focusable="<stable_key>"
//
//  where the key is a domain identifier (`"all"`, `"daily"`,
//  `"discord_webhook"`, `"discord_update"`, `"row_<session_id>"`,
//  `"reindex"`, etc.). The cursor controller queries the *focused
//  scope* (the active sub-panel if any, otherwise the active panel)
//  for its direct `[data-tui-focusable]` descendants IN DOCUMENT ORDER
//  — that ordered list is the active focus ring.
//
//  `j` / ArrowDown moves to next; `k` / ArrowUp moves to previous.
//  Movement clamps at the boundaries (no wrap — vim convention is no-op
//  past the edge so the user can `j` repeatedly without falling off).
//
//  The focused focusable gets `data-tui-focusable-focused="yes"` —
//  CSS paints a section-accent tint (per FB-99 lock; tint only, no
//  outline).
//
//  --- DYNAMIC LIST ---
//
//  Elements can be added or removed at runtime:
//
//    * a Stimulus controller (e.g. reindex-action) hides its idle slot
//      while a reindex is in flight; the `offsetParent === null`
//      filter automatically drops `[hidden]` / display:none nodes from
//      the focus ring. When the running slot flips back to idle, the
//      filter re-includes it.
//    * a controller can explicitly disable a focusable by setting
//      `data-tui-focusable-disabled="yes"` without hiding the element
//      (notification toggle while async save commits). The filter
//      drops disabled focusables.
//    * Cable broadcasts mutate the DOM via the relevant controller —
//      no special wiring needed on this side; the next j/k re-reads
//      the focus list.
//
//  --- MODE MODEL ---
//
//    NORMAL (default): keyboard navigation owns the screen.
//      - SPACE  → leader menu (owned by leader_menu_controller, not us)
//      - TAB         → advance to next panel in DOM order (wraps around).
//                      No-op when a dialog is open or focus is on a form
//                      input (browser default takes over).
//      - Shift-TAB   → retreat to previous panel in DOM order (wraps).
//                      Same guards as TAB.
//      - h/j/k/l + arrows           → INSIDE the focused panel
//                                     (sub-panels OR focusables — never
//                                     both at the same time).
//      - i      → enter INSERT mode AT CURRENT CURSOR LOCATION.
//      - Esc    → exit any input + return to NORMAL (always).
//
//    INSERT: input / checkbox / textarea has the keyboard.
//      - Esc    → blur active element, exit INSERT, return to NORMAL.
//      - SPACE  → if the focused focusable IS a checkbox (or contains
//                 one), toggle it. Otherwise pass through.
//      - j/k/ArrowDown/ArrowUp when active element is NOT a text input
//                 → advance focusable cursor (auto-focus the focusable's
//                 input/checkbox/button so SPACE / typing still lands
//                 somewhere meaningful).
//      - Any other key → passes through to the active element.
//
//    Mode auto-transitions:
//      - focusin on text input / textarea / [contenteditable] /
//        input[type=checkbox] → enter INSERT.
//      - focusout when next target isn't another input → exit INSERT.
//
//    Mode broadcasts on every transition:
//      document.dispatchEvent(
//        new CustomEvent("tui:mode-changed", { detail: { mode } })
//      )
//      → consumed by tui_bottom_status_bar_controller to repaint the
//      mode lozenge.
//
//  --- 3-LEVEL CURSOR HIERARCHY ---
//
//    Level 1 — PANEL.
//      Targets: elements with data-tui-cursor-target="panel".
//      Marker:  data-tui-cursor-focused="yes" on the focused panel.
//      Keys:    TAB (forward), Shift-TAB (backward) — DOM order, wraps.
//
//    Level 2 — SUB-PANEL (when present in focused panel).
//      Targets: elements with data-tui-cursor-target="sub-panel"
//               INSIDE the focused panel.
//      Marker:  data-tui-cursor-sub-panel-focused="yes".
//      Keys:    h/ArrowLeft + l/ArrowRight + j/ArrowDown + k/ArrowUp
//               cycle sub-panels (clamped) UNLESS the sub-panel has
//               its own focus list — then j/k drive the focus list
//               and h/l cycle between sub-panels.
//
//    Level 3 — FOCUSABLE (data-tui-focusable inside focused scope).
//      The focused scope is the active sub-panel if any, otherwise
//      the active panel. j/k moves within the focus list (clamped).
//      Visual marker: data-tui-focusable-focused="yes" on the element.
//
//  --- MOUSE / KEYBOARD SYNC ---
//
//    Click anywhere → walks ancestors looking for panel / sub-panel /
//    focusable markers; syncs the matching index when found.
//
//  --- TST BREADCRUMB EVENTS (FB-47 + FB-101) ---
//
//    Every focus change dispatches `tui:panel-focus-changed` on
//    document with `{ panel, subPanel }`.
//
//  =========================================================================

const INPUT_SELECTOR = [
  'input[type="text"]',
  'input[type="url"]',
  'input[type="email"]',
  'input[type="password"]',
  'input[type="number"]',
  'input[type="search"]',
  'input[type="tel"]',
  'input:not([type])',
  "textarea",
  '[contenteditable=""]',
  '[contenteditable="true"]'
].join(", ")

const FOCUSABLE_INPUT_SELECTOR = [
  INPUT_SELECTOR,
  'input[type="checkbox"]',
  'input[type="radio"]'
].join(", ")

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.mode = "normal"
    this.focusedIndex = 0
    this.subPanelIndex = 0
    this.focusableIndex = 0
    // FB-179 (2026-05-21) — saved focusable index for restoring panel
    // scope after a dialog closes.
    this.savedScopeIndex = null

    this.boundKey = this.handleKey.bind(this)
    this.boundFocusIn = this.handleFocusIn.bind(this)
    this.boundFocusOut = this.handleFocusOut.bind(this)
    this.boundClick = this.handleClick.bind(this)

    document.addEventListener("keydown", this.boundKey)
    document.addEventListener("focusin", this.boundFocusIn)
    document.addEventListener("focusout", this.boundFocusOut)
    document.addEventListener("click", this.boundClick, true)

    // FB-179 (2026-05-21) — watch every <dialog> [open] attribute. When
    // a dialog opens, save the current panel focusable index and reset
    // the cursor to the dialog's first focusable. When the dialog
    // closes, restore the saved index against the panel scope.
    this.dialogObserver = new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.type !== "attributes" || m.attributeName !== "open") continue
        const dialog = m.target
        if (dialog.hasAttribute("open")) {
          this.handleDialogOpened(dialog)
        } else {
          this.handleDialogClosed(dialog)
        }
      }
    })
    document.querySelectorAll("dialog").forEach((dialog) => {
      this.dialogObserver.observe(dialog, { attributes: true, attributeFilter: ["open"] })
    })

    this.applyFocus()
    // 2026-05-23 — re-emit the focus-changed event on the next microtask
    // so subscribers that mount after this controller's `connect()` (the
    // breadcrumb / TST controllers) pick up the first panel's title
    // on initial paint. Without this, the first emit fires before
    // those controllers register their listeners and the breadcrumb
    // stays blank until the user moves the cursor.
    queueMicrotask(() => this.emitFocusChange())
    // Belt-and-suspenders: also re-emit after the next macrotask, which
    // covers the case where Stimulus mounts subscribers via a later
    // turn of the event loop (e.g. Turbo's `turbo:load` happens after
    // `DOMContentLoaded`).
    setTimeout(() => this.emitFocusChange(), 0)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey)
    document.removeEventListener("focusin", this.boundFocusIn)
    document.removeEventListener("focusout", this.boundFocusOut)
    document.removeEventListener("click", this.boundClick, true)
    if (this.dialogObserver) {
      this.dialogObserver.disconnect()
      this.dialogObserver = null
    }
  }

  handleDialogOpened(_dialog) {
    // Save the panel-scope index, reset cursor into the dialog scope.
    this.savedScopeIndex = this.focusableIndex
    this.focusableIndex = 0
    this.applyFocusableFocus()
  }

  handleDialogClosed(_dialog) {
    // Dialog gone — restore the saved panel-scope index. focusedScope()
    // will now return the panel again on its own.
    this.focusableIndex = this.savedScopeIndex || 0
    this.savedScopeIndex = null
    this.applyFocusableFocus()
  }

  // ===================== MODE STATE MACHINE =====================

  enterInsertMode() {
    if (this.mode === "insert") return
    this.mode = "insert"
    this.broadcastMode()
  }

  exitInsertMode() {
    if (this.mode === "normal") return
    this.mode = "normal"
    this.broadcastMode()
  }

  broadcastMode() {
    document.dispatchEvent(
      new CustomEvent("tui:mode-changed", { detail: { mode: this.mode } })
    )
  }

  handleFocusIn(event) {
    const t = event.target
    if (t && t.matches && t.matches(FOCUSABLE_INPUT_SELECTOR)) {
      this.enterInsertMode()
    }
  }

  handleFocusOut(event) {
    const t = event.target
    if (!t || !t.matches || !t.matches(FOCUSABLE_INPUT_SELECTOR)) return
    const next = event.relatedTarget
    if (next && next.matches && next.matches(FOCUSABLE_INPUT_SELECTOR)) return
    // FB-167 guard: if the focusout was triggered by a DOM hide (e.g. the
    // header-row swap in sessions-bulk-revoke hiding the defaultHeader row
    // while the header checkbox had focus), the losing element is now inside
    // a `[hidden]` ancestor. This is NOT a user-driven focus exit — it is a
    // side-effect of a Stimulus controller mutating the DOM. Don't exit
    // INSERT; instead re-anchor native focus on the current focusable so the
    // cursor stays in INSERT mode with the correct element focused.
    if (t.closest("[hidden]")) {
      // Defer one tick so the DOM mutation fully settles before we try to
      // re-focus. Without the timeout, focus() is a no-op on the newly
      // visible element in some browsers.
      setTimeout(() => { this.refocusForFocusable() }, 0)
      return
    }
    this.exitInsertMode()
  }

  // ===================== KEY DISPATCH =====================
  //
  // Panel-level keys (TAB / Shift-TAB) are evaluated FIRST, BEFORE any
  // mode-specific branch — they must work identically in NORMAL and INSERT.
  // This is the FB-165 regression fix: previously FB-143's `tabIntoFocusedRow`
  // trapped Tab inside a focused row when the row had internal focusable
  // elements, requiring N tabs per panel × N actions per row to escape.
  // Per the 2026-05-21 user-locked architecture (updated 2026-05-24 to drop
  // spatial Ctrl-hjkl), Tab/Shift-Tab are the sole panel-level keys —
  // focusable-level cycling lives on j/k.
  //
  // TAB / Shift-TAB guard: when focus is inside a form input / textarea /
  // contenteditable / select, we do NOT intercept — the browser handles
  // text-field tab order naturally. When a dialog is open, shouldIgnore()
  // already bails so TAB falls through to the dialog's own focus trap.
  handleKey(event) {
    if (this.shouldIgnore(event)) return

    // --- Panel-level keys — always active, all modes. ---
    if (event.key === "Tab" && !event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
      // Let the browser handle TAB when focus is on a form input / select.
      const active = document.activeElement
      if (active && active.matches && active.matches(INPUT_SELECTOR + ", select")) return
      event.preventDefault()
      event.stopPropagation()
      this.nextPanel()
      return
    }
    if (event.key === "Tab" && event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
      // Let the browser handle Shift-TAB when focus is on a form input / select.
      const active = document.activeElement
      if (active && active.matches && active.matches(INPUT_SELECTOR + ", select")) return
      event.preventDefault()
      event.stopPropagation()
      this.previousPanel()
      return
    }

    // --- INSERT mode branch. ---
    if (this.mode === "insert") {
      this.handleInsertKey(event)
      return
    }

    // --- NORMAL mode branch. ---
    this.handleNormalKey(event)
  }

  shouldIgnore(event) {
    // FB-179 (2026-05-21) — when a dialog is open, the cursor scope
    // shifts to that dialog. If the dialog declares its own
    // [data-tui-focusable] children, we DRIVE j/k/Tab navigation inside
    // those (the new dialog-scope behavior). If the dialog has no
    // focusables of its own, the dialog owns its keyboard — bail.
    const openDialog = document.querySelector("dialog[open]")
    if (openDialog) {
      const hasOwnFocusables = openDialog.querySelector("[data-tui-focusable]")
      if (!hasOwnFocusables) return true
    }
    // Modifier combos we don't handle (Alt-*, Meta-*, etc.).
    if (event.altKey || event.metaKey) return true
    return false
  }

  handleInsertKey(event) {
    const k = event.key

    if (k === "Escape") {
      const active = document.activeElement
      if (active && typeof active.blur === "function") active.blur()
      this.exitInsertMode()
      event.preventDefault()
      event.stopPropagation()
      return
    }

    if (k === " ") {
      const active = document.activeElement
      const onTextInput = active && active.matches && active.matches(INPUT_SELECTOR)
      if (onTextInput) return
      // 2026-05-24 (sync-rebuild) — SPACE in INSERT mode toggles the
      // focused action focusable. The helper covers BOTH the checkbox
      // path (e.g., notification toggle) AND the action-button path
      // (e.g., Tui::SyncIndicatorComponent in :target mode). Always
      // preventDefault when the helper succeeds so the native button
      // SPACE keyup activation does NOT fire a second click.
      if (this.toggleFocusedFocusableCheckbox()) {
        event.preventDefault()
        event.stopPropagation()
      }
      return
    }

    if (k === "j" || k === "k" || k === "ArrowDown" || k === "ArrowUp") {
      const active = document.activeElement
      const onTextInput = active && active.matches && active.matches(INPUT_SELECTOR)
      if (!onTextInput) {
        if (k === "j" || k === "ArrowDown") {
          this.focusNext()
        } else {
          this.focusPrev()
        }
        this.refocusForFocusable()
        event.preventDefault()
        event.stopPropagation()
      }
      return
    }
  }

  handleNormalKey(event) {
    // Defensive: if focus is stuck on an input despite NORMAL mode,
    // bail so typing into the input still works.
    const t = event.target
    if (t && t.matches && t.matches(INPUT_SELECTOR + ", select")) return

    let handled = false
    const k = event.key

    // FB (2026-05-22) — `i` is a MODE-LEVEL key, not a focusable-level
    // key. It flips NORMAL→INSERT regardless of whether the screen has
    // any focusables (empty home, dialog-less screens, layout-only
    // pages). Evaluated FIRST so the mode lozenge always responds to
    // `i`. When focusables ARE present, refocusForFocusable() still
    // anchors native focus on the current focusable so SPACE / typing
    // lands somewhere meaningful — but absent focusables it's a no-op.
    if (k === "i" && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
      this.enterInsertMode()
      this.refocusForFocusable()
      event.preventDefault()
      event.stopPropagation()
      return
    }

    if (k === "Escape") {
      handled = true
    } else if (!event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
      // FB-170 (2026-05-21 user-locked) — FLAT TRAVERSAL.
      // j/k ALWAYS cycles ALL focusables across the focused panel in
      // document order. Sub-panels are visual grouping only, not nav
      // stops. h/l still cycles between sub-panels when they exist —
      // sub-panels remain a useful affordance for jumping past a
      // group's focusables, but they no longer scope j/k.
      const mode = this.insidePanelMode()
      const hasFocusables = this.focusablesInFocusedScope().length > 0
      const hasSubPanels = mode === "sub-panel"

      if (hasFocusables) {
        switch (k) {
          case "j": case "ArrowDown":
            this.focusNext(); handled = true; break
          case "k": case "ArrowUp":
            this.focusPrev(); handled = true; break
          case "h": case "ArrowLeft":
            if (hasSubPanels) this.previousSubPanel()
            handled = true; break
          case "l": case "ArrowRight":
            if (hasSubPanels) this.nextSubPanel()
            handled = true; break
          // 2026-05-24 — NORMAL-mode SPACE is OWNED by the leader menu
          // controller, per the contract docblock at the top of this
          // file: "SPACE → leader menu (owned by leader_menu_controller,
          // not us)". We do NOT short-circuit the keystroke here, even
          // when a focusable is focused — otherwise the user has to
          // exit-cursor-focus to use `Space s` (the master TST sync
          // toggle) or any other leader entry. Toggling a focused
          // checkbox / button via SPACE is INSERT mode's job.
          case "Enter":
            if (this.triggerFocusedFocusableAction()) handled = true
            break
        }
      } else if (hasSubPanels) {
        // Panel has sub-panels but NO focusables anywhere — hjkl
        // cycles between sub-panels (legacy affordance for empty
        // grouping panels, e.g., placeholder/info-only sections).
        switch (k) {
          case "h": case "ArrowLeft":
          case "k": case "ArrowUp":
            this.previousSubPanel(); handled = true; break
          case "l": case "ArrowRight":
          case "j": case "ArrowDown":
            this.nextSubPanel(); handled = true; break
        }
      }

      // `i` handler relocated to the top of handleNormalKey — it
      // fires regardless of focusables so empty screens (no panels,
      // no dialog) still flip the lozenge.
    }

    if (handled) {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  // ===================== PANEL LEVEL =====================

  nextPanel() {
    if (this.panelTargets.length === 0) return
    this.focusedIndex = (this.focusedIndex + 1) % this.panelTargets.length
    this.subPanelIndex = 0
    this.focusableIndex = 0
    this.applyFocus()
  }

  previousPanel() {
    if (this.panelTargets.length === 0) return
    this.focusedIndex =
      (this.focusedIndex - 1 + this.panelTargets.length) % this.panelTargets.length
    this.subPanelIndex = 0
    this.focusableIndex = 0
    this.applyFocus()
  }

  applyFocus() {
    this.panelTargets.forEach((el, idx) => {
      if (idx === this.focusedIndex) {
        el.dataset.tuiCursorFocused = "yes"
        el.scrollIntoView({ block: "nearest", behavior: "smooth" })
      } else {
        delete el.dataset.tuiCursorFocused
      }
    })
    this.applySubPanelFocus()
    this.applyFocusableFocus()
    this.emitFocusChange()
  }

  // ===================== INSIDE-PANEL: WHICH MODE? =====================

  insidePanelMode() {
    const focused = this.panelTargets[this.focusedIndex]
    if (!focused) return "none"
    if (this.subPanelsInFocusedPanel().length > 0) return "sub-panel"
    return "panel"
  }

  // ===================== SUB-PANEL LEVEL =====================

  subPanelsInFocusedPanel() {
    const focused = this.panelTargets[this.focusedIndex]
    if (!focused) return []
    const all = Array.from(
      focused.querySelectorAll('[data-tui-cursor-target="sub-panel"]')
    )
    return all.filter(
      (el) => el.closest('[data-tui-cursor-target="panel"]') === focused
    )
  }

  focusedSubPanel() {
    const subs = this.subPanelsInFocusedPanel()
    if (subs.length === 0) return null
    return subs[this.subPanelIndex] || null
  }

  nextSubPanel() {
    const subs = this.subPanelsInFocusedPanel()
    if (subs.length === 0) return
    this.subPanelIndex = Math.min(this.subPanelIndex + 1, subs.length - 1)
    this.focusableIndex = 0
    this.applySubPanelFocus()
    this.applyFocusableFocus()
    this.emitFocusChange()
  }

  previousSubPanel() {
    const subs = this.subPanelsInFocusedPanel()
    if (subs.length === 0) return
    this.subPanelIndex = Math.max(this.subPanelIndex - 1, 0)
    this.focusableIndex = 0
    this.applySubPanelFocus()
    this.applyFocusableFocus()
    this.emitFocusChange()
  }

  applySubPanelFocus() {
    const subs = this.subPanelsInFocusedPanel()
    document
      .querySelectorAll(
        '[data-tui-cursor-target="sub-panel"][data-tui-cursor-sub-panel-focused="yes"]'
      )
      .forEach((el) => {
        delete el.dataset.tuiCursorSubPanelFocused
      })
    if (subs.length === 0) {
      this.subPanelIndex = 0
      return
    }
    if (this.subPanelIndex >= subs.length) this.subPanelIndex = subs.length - 1
    if (this.subPanelIndex < 0) this.subPanelIndex = 0
    const active = subs[this.subPanelIndex]
    if (active) {
      active.dataset.tuiCursorSubPanelFocused = "yes"
      active.scrollIntoView({ block: "nearest" })
    }
  }

  // ===================== FOCUSABLE LEVEL =====================
  //
  // FB-170 (2026-05-21 user-locked) — FLAT TRAVERSAL.
  // The "focused scope" is ALWAYS the top-level focused panel. j/k
  // cycles through every focusable inside that panel in DOCUMENT ORDER,
  // regardless of which sub-panel each focusable lives in. Sub-panels
  // are visual grouping (boxes for legibility), NOT navigational stops.
  // Empty sub-panels contribute no focusables and are naturally skipped.
  //
  // Example: pressing j inside the stack panel cycles
  //   Meilisearch [reindex] → Voyage [reindex] → wrap (clamped)
  // Empty sub-panels (Redis, Postgres, assets, notes) are not stops.

  focusedScope() {
    // FB-179 (2026-05-21) — an open <dialog> wins the cursor scope.
    // When a dialog is open, j/k/Tab cycle the dialog's focusables;
    // Esc closes the dialog and scope reverts (via handleDialogClosed
    // restoring savedScopeIndex). When no dialog is open, fall back to
    // the focused top-level panel.
    const openDialog = document.querySelector("dialog[open]")
    if (openDialog) return openDialog
    return this.panelTargets[this.focusedIndex] || null
  }

  focusablesInFocusedScope() {
    const scope = this.focusedScope()
    if (!scope) return []
    const all = Array.from(scope.querySelectorAll("[data-tui-focusable]"))
    // FB-179 (2026-05-21) — when scope is a <dialog>, skip the
    // closest-panel filter since dialog focusables aren't under a panel
    // ancestor. Apply only the disabled / hidden filters.
    const isDialogScope = scope.tagName === "DIALOG"
    return all.filter((el) => {
      if (!isDialogScope) {
        // Only focusables whose closest PANEL is this panel — skips
        // focusables owned by a nested panel (defensive; shouldn't
        // happen in practice). `closest('[data-tui-cursor-target="panel"]')`
        // walks up DOM and stops at the first PANEL ancestor, naturally
        // ignoring sub-panel wrappers (which use the "sub-panel" attribute
        // value, not "panel"). That's the flat-traversal mechanism.
        const ownPanel = el.closest('[data-tui-cursor-target="panel"]')
        if (ownPanel !== scope) return false
      }
      // Skip disabled (async save in flight, etc.).
      if (el.dataset.tuiFocusableDisabled === "yes") return false
      // Skip hidden / display:none / detached.
      if (el.offsetParent === null) {
        // `offsetParent` is null for `position: fixed` elements that are
        // still visible — but our focusables aren't fixed-position, so
        // this filter is safe for the surface we control.
        return false
      }
      return true
    })
  }

  focusNext() {
    const list = this.focusablesInFocusedScope()
    if (list.length === 0) return
    this.focusableIndex = Math.min(this.focusableIndex + 1, list.length - 1)
    this.applyFocusableFocus()
  }

  focusPrev() {
    const list = this.focusablesInFocusedScope()
    if (list.length === 0) return
    this.focusableIndex = Math.max(this.focusableIndex - 1, 0)
    this.applyFocusableFocus()
  }

  applyFocusableFocus() {
    // FB-174 (2026-05-21) — bulletproof stale-marker clear.
    //
    // Previously used `delete el.dataset.tuiFocusableFocused` which
    // SHOULD remove the attribute but in practice some browsers / DOM
    // states leave the attribute around in a "removed but still
    // selector-matching" form (observed: pressing j 6 times leaves
    // visible orange tint on rows 0..5 even though the controller
    // logs claim only row 6 is the active focusable). `removeAttribute`
    // is the spec-required form that guarantees the attribute node
    // is detached from the element AND the CSS selector
    // `[data-tui-focusable-focused="yes"]` stops matching immediately.
    //
    // Document-wide query (not just focused scope) is intentional —
    // panel switches and click syncs may have planted markers in
    // sibling panels that the focused-scope query would miss.
    document
      .querySelectorAll("[data-tui-focusable-focused]")
      .forEach((el) => {
        el.removeAttribute("data-tui-focusable-focused")
      })
    const list = this.focusablesInFocusedScope()
    if (list.length === 0) {
      this.focusableIndex = 0
      return
    }
    if (this.focusableIndex >= list.length) this.focusableIndex = list.length - 1
    if (this.focusableIndex < 0) this.focusableIndex = 0
    const active = list[this.focusableIndex]
    if (active) {
      active.setAttribute("data-tui-focusable-focused", "yes")
      active.scrollIntoView({ block: "nearest" })
      // FB-184 (2026-05-21) — auto-sync sub-panel marker to the focused
      // focusable's parent sub-panel. FB-169 made stack panel j/k traverse
      // flat across sub-panel focusables; this re-couples the visible
      // sub-panel border accent to the focused focusable so the user
      // sees which zone owns the cursor. Walks up to the nearest
      // `[data-tui-cursor-target="sub-panel"]` ancestor and syncs
      // `this.subPanelIndex` against the focused panel's sub-panel list.
      this.syncSubPanelFromFocusable(active)
    }
  }

  // FB-184 (2026-05-21). When a focusable becomes active via j/k or
  // click, derive its parent sub-panel (if any) and re-align the
  // sub-panel marker. No-op when the focusable lives outside any
  // sub-panel (e.g. focusables directly under a panel without sub-panel
  // grouping, or dialog-scope focusables).
  syncSubPanelFromFocusable(active) {
    if (!active || !active.closest) return
    // FB-185 — if the focusable lives in the panel's own title-actions slot
    // (e.g. the stack panel's [ ] sync button), it is NOT inside any
    // sub-panel. Bail early so the sub-panel marker doesn't shift.
    if (active.closest('.pito-pane__title-actions')) return
    const subPanel = active.closest('[data-tui-cursor-target="sub-panel"]')
    if (!subPanel) return
    const subs = this.subPanelsInFocusedPanel()
    const idx = subs.indexOf(subPanel)
    if (idx === -1) return
    if (idx === this.subPanelIndex) return
    this.subPanelIndex = idx
    this.applySubPanelFocus()
    // 2026-05-24 — broadcast a focus-changed event so downstream
    // listeners (tui-breadcrumb, etc.) see the new sub-panel title.
    // Without this, j/k crossing a sub-panel boundary updates the
    // sub-panel marker but the breadcrumb stays pinned to the previous
    // sub-panel title.
    this.emitFocusChange()
  }

  focusedFocusable() {
    const list = this.focusablesInFocusedScope()
    return list[this.focusableIndex] || null
  }

  // SPACE on a focused focusable.
  //
  // 2026-05-24 — extended past the original "checkbox only" semantic.
  // The focused focusable may be:
  //   1. an `<input type="checkbox">` (or contain one) — toggle the
  //      checkbox via .click(). Original case.
  //   2. an action-style focusable that is itself a `<button>` (e.g.
  //      `Tui::SyncIndicatorComponent` in `:target` mode renders as a
  //      `<button.tui-sync-word--target>`). SPACE in INSERT must fire
  //      the action so the user can toggle sync without leaving the
  //      keyboard. CLAUDE.md lock 2026-05-24: "x key is NOT a toggle;
  //      INSERT + SPACE is the only toggle path".
  //   3. otherwise no-op (return false so the leader menu controller's
  //      own SPACE guard can decide if it wants the keystroke).
  //
  // FB-167 (2026-05-21) — do NOT blur after toggle. The previous blur
  // triggered focusout → handleFocusOut → exitInsertMode, kicking the
  // user out of INSERT after every SPACE toggle. User contract: only
  // Esc exits INSERT, period. Leaving focus on the focusable keeps the
  // native focus ring + INSERT lozenge alive across repeated toggles.
  toggleFocusedFocusableCheckbox() {
    const el = this.focusedFocusable()
    if (!el) return false
    // Path 1 — checkbox or contains-a-checkbox.
    const checkbox =
      el.matches && el.matches('input[type="checkbox"]')
        ? el
        : el.querySelector('input[type="checkbox"]')
    if (checkbox) {
      checkbox.click()
      return true
    }
    // Path 2 — action-style focusable. The canonical case is the
    // Tui::SyncIndicatorComponent in :target mode, where the focusable
    // host IS the `<button>`. Path 2 also covers the more general case
    // of an action focusable that WRAPS a button (no current call site,
    // but defensible against future call sites that wrap the button
    // with an outer span carrying the focusable attrs).
    //
    // 2026-05-24 (sync-rebuild) — generalised from "is-a-button" to
    // "is-or-contains-a-button" so a future wrapper-around-button
    // focusable picks up the SPACE toggle without re-deriving Path 2.
    if (el.dataset && el.dataset.tuiFocusableStyle === "action") {
      const button =
        (el.matches && el.matches('button'))
          ? el
          : el.querySelector('button')
      if (button) {
        button.click()
        return true
      }
    }
    return false
  }

  // Enter triggers the focusable's primary action — if the focusable IS
  // a button/anchor click it; otherwise look for [data-row-action="primary"]
  // (legacy) or the first button/anchor inside.
  triggerFocusedFocusableAction() {
    const el = this.focusedFocusable()
    if (!el) return false
    if (el.matches && el.matches('button, a[href], input[type="submit"]')) {
      el.click()
      return true
    }
    const action =
      el.querySelector('[data-row-action="primary"]') ||
      el.querySelector('button, a[href], input[type="submit"]')
    if (!action) return false
    action.click()
    return true
  }

  // After j/k moves the focusable cursor (in INSERT mode, or on `i` entry),
  // place native focus on the focusable's input/checkbox/button so SPACE
  // / typing lands somewhere meaningful.
  refocusForFocusable() {
    const el = this.focusedFocusable()
    if (!el) return
    let target = null
    if (el.matches && el.matches('input, button, a[href], textarea, select')) {
      target = el
    } else {
      target =
        el.querySelector('input[type="checkbox"]') ||
        el.querySelector(INPUT_SELECTOR) ||
        el.querySelector('button, a[href], input[type="submit"]')
    }
    if (target && typeof target.focus === "function") {
      target.focus({ preventScroll: true })
      return
    }
    const active = document.activeElement
    if (active && typeof active.blur === "function") active.blur()
  }

  // ===================== MOUSE → KEYBOARD SYNC =====================

  handleClick(event) {
    const t = event.target
    if (!t || !t.closest) return

    // Sync panel index on panel click.
    const panel = t.closest('[data-tui-cursor-target="panel"]')
    if (panel) {
      const panelIdx = this.panelTargets.indexOf(panel)
      if (panelIdx !== -1 && panelIdx !== this.focusedIndex) {
        this.focusedIndex = panelIdx
        this.subPanelIndex = 0
        this.focusableIndex = 0
        this.applyFocus()
      }
    }

    // Sync sub-panel index on sub-panel click.
    const subPanel = t.closest('[data-tui-cursor-target="sub-panel"]')
    if (subPanel) {
      const subs = this.subPanelsInFocusedPanel()
      const subIdx = subs.indexOf(subPanel)
      if (subIdx !== -1 && subIdx !== this.subPanelIndex) {
        this.subPanelIndex = subIdx
        this.focusableIndex = 0
        this.applySubPanelFocus()
        this.applyFocusableFocus()
        this.emitFocusChange()
      }
    }

    // Sync focusable index on focusable click.
    const focusable = t.closest("[data-tui-focusable]")
    if (focusable) {
      const list = this.focusablesInFocusedScope()
      const idx = list.indexOf(focusable)
      if (idx !== -1 && idx !== this.focusableIndex) {
        this.focusableIndex = idx
        this.applyFocusableFocus()
      }
    }
  }

  // ===================== BREADCRUMB BROADCAST (FB-47 + FB-101) =====================

  emitFocusChange() {
    const focused = this.panelTargets[this.focusedIndex]
    if (!focused) return
    const panelTitle = focused.dataset.panelTitle ?? ""
    let subPanelTitle = null
    if (this.insidePanelMode() === "sub-panel") {
      const subs = this.subPanelsInFocusedPanel()
      const active = subs[this.subPanelIndex]
      if (active) {
        subPanelTitle = active.dataset.panelTitle ?? null
      }
    }
    document.dispatchEvent(
      new CustomEvent("tui:panel-focus-changed", {
        detail: { panel: panelTitle, subPanel: subPanelTitle, title: panelTitle }
      })
    )
  }
}
