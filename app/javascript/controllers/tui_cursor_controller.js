import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tui-cursor"
//
// =========================================================================
//  CONTRACT (locked 2026-05-20 for FB-100, FB-98, FB-101, FB-112, FB-113, FB-114)
// =========================================================================
//
//  Vim-inspired NORMAL / INSERT mode model + 3-level cursor hierarchy.
//
//  --- MODE MODEL ---
//
//    NORMAL (default): keyboard navigation owns the screen.
//      - SPACE  → leader menu (owned by leader_menu_controller, not us)
//      - TAB / Shift-TAB / Ctrl-hjkl → panel-level nav
//      - h/j/k/l + arrows           → INSIDE the focused panel
//                                     (sub-panels OR rows, whichever the
//                                     panel hosts)
//      - i      → enter INSERT (only if focused element is/contains an input)
//      - Esc    → exit any input + return to NORMAL (always)
//
//    INSERT: text input has the keyboard. We only listen for Esc.
//      - Esc    → blur input, exit INSERT, return to NORMAL
//      - Any other key → passes through to the input (no preventDefault)
//
//    Mode auto-transitions:
//      - focusin on input/textarea/[contenteditable] → enter INSERT
//      - focusout when next target isn't another input → exit INSERT
//
//    Mode broadcasts on every transition:
//      document.dispatchEvent(
//        new CustomEvent("tui:mode-changed", { detail: { mode: "normal" | "insert" } })
//      )
//      → consumed by tui_bottom_status_bar_controller to repaint the mode lozenge
//
//  --- 3-LEVEL CURSOR HIERARCHY ---
//
//    Level 1 — PANEL.
//      Targets: elements with data-tui-cursor-target="panel"
//      Marker:  data-tui-cursor-focused="yes" on the focused panel
//      Keys:    TAB, Shift-TAB, Ctrl-h, Ctrl-l, Ctrl-j, Ctrl-k
//
//    Level 2 — INSIDE PANEL.
//      Branches per focused panel content:
//        a) Panel has data-tui-cursor-target="sub-panel" children
//             → h/ArrowLeft + l/ArrowRight + j/ArrowDown + k/ArrowUp
//               cycle sub-panels (linear index, clamped)
//             → focused sub-panel gets data-tui-cursor-sub-panel-focused="yes"
//             → dispatches tui:panel-focus-changed with sub-panel breadcrumb
//        b) Panel has data-tui-cursor-target="row" children (and no sub-panels)
//             → j/ArrowDown / k/ArrowUp cycle rows
//             → h/ArrowLeft / l/ArrowRight no-op (reserved for L3 future)
//             → focused row gets data-tui-cursor-row-focused="yes"
//             → SPACE on row → click first input[type=checkbox] inside the row
//             → Enter on row → click [data-row-action="primary"] inside the row
//        c) Neither → all hjkl + arrows no-op silently
//
//    Level 3 — INSIDE SUB-PANEL (deferred — FB-113 future work).
//      Stub: sub-panels with rows inside them aren't navigable yet.
//      Stack sub-panels (Redis, PostgreSQL, etc.) host KV-style metric
//      rows that aren't user-actionable. Revisit when a sub-panel ships
//      with row-level actions.
//
//  --- MOUSE / KEYBOARD SYNC (FB-98) ---
//
//    Click on a data-tui-cursor-target="row" → updates this.rowIndex
//    and re-applies the focus marker so the cursor follows the click.
//    Same delegate handles panels and sub-panels (defensive — keyboard
//    + mouse never diverge).
//
//  --- TST BREADCRUMB EVENTS (FB-47 + FB-101) ---
//
//    Every focus change dispatches `tui:panel-focus-changed` on document.
//    Detail shape:
//
//      { panel: "<panel title>", subPanel: "<sub-panel title>" | null }
//
//    The tui-status-bar controller listens and rebuilds the .sb-section
//    span as either:
//
//      <panel>                              (no sub-panel focused)
//      <panel>:(<sub-panel>)                (sub-panel focused)
//
//  =========================================================================

// Sentinel selector matching the elements that count as "text inputs".
// Excludes checkboxes / radios — those are NORMAL-mode targets (toggled
// via SPACE on focused row).
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

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.mode = "normal"
    this.focusedIndex = 0
    this.rowIndex = 0
    this.subPanelIndex = 0

    this.boundKey = this.handleKey.bind(this)
    this.boundFocusIn = this.handleFocusIn.bind(this)
    this.boundFocusOut = this.handleFocusOut.bind(this)
    this.boundClick = this.handleClick.bind(this)

    document.addEventListener("keydown", this.boundKey)
    document.addEventListener("focusin", this.boundFocusIn)
    document.addEventListener("focusout", this.boundFocusOut)
    document.addEventListener("click", this.boundClick, true)

    this.applyFocus()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey)
    document.removeEventListener("focusin", this.boundFocusIn)
    document.removeEventListener("focusout", this.boundFocusOut)
    document.removeEventListener("click", this.boundClick, true)
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
    if (t && t.matches && t.matches(INPUT_SELECTOR)) {
      this.enterInsertMode()
    }
  }

  handleFocusOut(event) {
    const t = event.target
    if (!t || !t.matches || !t.matches(INPUT_SELECTOR)) return
    // If focus is moving to another text input, stay in INSERT.
    const next = event.relatedTarget
    if (next && next.matches && next.matches(INPUT_SELECTOR)) return
    this.exitInsertMode()
  }

  // ===================== KEY DISPATCH =====================

  handleKey(event) {
    // INSERT mode: only Esc is ours. Everything else is the input's.
    if (this.mode === "insert") {
      if (event.key === "Escape") {
        const active = document.activeElement
        if (active && typeof active.blur === "function") active.blur()
        this.exitInsertMode()
        event.preventDefault()
        event.stopPropagation()
      }
      return
    }

    // NORMAL mode. Bail when a dialog is open (leader menu, help, about).
    if (document.querySelector("dialog[open]")) return

    // Also bail if the event target is somehow still an input despite
    // NORMAL mode (defensive: a stray focused-but-not-blurred control).
    const t = event.target
    if (t && t.matches && t.matches(INPUT_SELECTOR + ", select")) return

    let handled = false
    const k = event.key

    if (k === "Escape") {
      // No-op in NORMAL (already there), but absorb it so background
      // listeners don't react twice.
      handled = true
    } else if (k === "Tab" && !event.shiftKey && !event.ctrlKey && !event.metaKey) {
      this.nextPanel(); handled = true
    } else if (k === "Tab" && event.shiftKey && !event.ctrlKey && !event.metaKey) {
      this.previousPanel(); handled = true
    } else if (event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
      switch (k) {
        case "h": this.previousPanel(); handled = true; break
        case "l": this.nextPanel(); handled = true; break
        case "j": this.nextPanel(); handled = true; break
        case "k": this.previousPanel(); handled = true; break
      }
    } else if (!event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey) {
      // Plain hjkl / arrows / Space / Enter / i — inside-panel work.
      const mode = this.insidePanelMode()
      if (mode === "sub-panel") {
        switch (k) {
          case "h":
          case "ArrowLeft":
          case "k":
          case "ArrowUp":
            this.previousSubPanel(); handled = true; break
          case "l":
          case "ArrowRight":
          case "j":
          case "ArrowDown":
            this.nextSubPanel(); handled = true; break
        }
      } else if (mode === "row") {
        switch (k) {
          case "j":
          case "ArrowDown":
            this.nextRow(); handled = true; break
          case "k":
          case "ArrowUp":
            this.previousRow(); handled = true; break
          case "h":
          case "ArrowLeft":
            // reserved (L3 future)
            handled = true; break
          case "l":
          case "ArrowRight":
            // reserved (L3 future)
            handled = true; break
          case " ":
            if (this.toggleFocusedRowCheckbox()) handled = true
            break
          case "Enter":
            if (this.triggerFocusedRowAction()) handled = true
            break
        }
      }

      // `i` enters INSERT if there's an input inside the focused panel
      // (or sub-panel / row) to land on. Mode-independent of nav mode.
      if (!handled && k === "i") {
        if (this.enterInsertFromFocus()) handled = true
      }
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
    this.rowIndex = 0
    this.subPanelIndex = 0
    this.applyFocus()
  }

  previousPanel() {
    if (this.panelTargets.length === 0) return
    this.focusedIndex =
      (this.focusedIndex - 1 + this.panelTargets.length) % this.panelTargets.length
    this.rowIndex = 0
    this.subPanelIndex = 0
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
    this.applyRowFocus()
    this.emitFocusChange()
  }

  // ===================== INSIDE-PANEL: WHICH MODE? =====================

  insidePanelMode() {
    const focused = this.panelTargets[this.focusedIndex]
    if (!focused) return "none"
    if (this.subPanelsInFocusedPanel().length > 0) return "sub-panel"
    if (this.rowsInFocusedPanel().length > 0) return "row"
    return "none"
  }

  // ===================== SUB-PANEL LEVEL =====================

  subPanelsInFocusedPanel() {
    const focused = this.panelTargets[this.focusedIndex]
    if (!focused) return []
    const all = Array.from(
      focused.querySelectorAll('[data-tui-cursor-target="sub-panel"]')
    )
    // Direct sub-panels of the focused panel only — exclude any that
    // belong to a nested panel target (defensive against deep layouts).
    return all.filter(
      (el) => el.closest('[data-tui-cursor-target="panel"]') === focused
    )
  }

  nextSubPanel() {
    const subs = this.subPanelsInFocusedPanel()
    if (subs.length === 0) return
    this.subPanelIndex = Math.min(this.subPanelIndex + 1, subs.length - 1)
    this.applySubPanelFocus()
    this.emitFocusChange()
  }

  previousSubPanel() {
    const subs = this.subPanelsInFocusedPanel()
    if (subs.length === 0) return
    this.subPanelIndex = Math.max(this.subPanelIndex - 1, 0)
    this.applySubPanelFocus()
    this.emitFocusChange()
  }

  applySubPanelFocus() {
    const subs = this.subPanelsInFocusedPanel()
    // Always clear sub-panel markers across ALL sub-panels in the DOM
    // (not just the focused panel) so a panel switch doesn't leave a
    // stale marker on an off-screen panel.
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

  // ===================== ROW LEVEL =====================

  rowsInFocusedPanel() {
    const focused = this.panelTargets[this.focusedIndex]
    if (!focused) return []
    // Skip rows when sub-panels are present (rows belong to a nested
    // L3 cursor that's deferred for now).
    const all = Array.from(
      focused.querySelectorAll('[data-tui-cursor-target="row"]')
    )
    return all.filter(
      (row) => row.closest('[data-tui-cursor-target="panel"]') === focused
    )
  }

  nextRow() {
    const rows = this.rowsInFocusedPanel()
    if (rows.length === 0) return
    this.rowIndex = Math.min(this.rowIndex + 1, rows.length - 1)
    this.applyRowFocus()
  }

  previousRow() {
    const rows = this.rowsInFocusedPanel()
    if (rows.length === 0) return
    this.rowIndex = Math.max(this.rowIndex - 1, 0)
    this.applyRowFocus()
  }

  applyRowFocus() {
    const rows = this.rowsInFocusedPanel()
    // Clear stale row markers everywhere — same defensive reset as
    // sub-panels above.
    document
      .querySelectorAll(
        '[data-tui-cursor-target="row"][data-tui-cursor-row-focused="yes"]'
      )
      .forEach((row) => {
        delete row.dataset.tuiCursorRowFocused
      })
    if (rows.length === 0) {
      this.rowIndex = 0
      return
    }
    if (this.rowIndex >= rows.length) this.rowIndex = rows.length - 1
    if (this.rowIndex < 0) this.rowIndex = 0
    const active = rows[this.rowIndex]
    if (active) {
      active.dataset.tuiCursorRowFocused = "yes"
      active.scrollIntoView({ block: "nearest" })
    }
  }

  focusedRow() {
    const rows = this.rowsInFocusedPanel()
    return rows[this.rowIndex] || null
  }

  // FB-100 — toggle the row's checkbox via the row's own input,
  // NOT by walking the checkbox as a separate cursor stop.
  toggleFocusedRowCheckbox() {
    const row = this.focusedRow()
    if (!row) return false
    const checkbox = row.querySelector('input[type="checkbox"]')
    if (!checkbox) return false
    checkbox.click()
    return true
  }

  triggerFocusedRowAction() {
    const row = this.focusedRow()
    if (!row) return false
    const action = row.querySelector('[data-row-action="primary"]')
    if (!action) return false
    action.click()
    return true
  }

  // ===================== MOUSE → KEYBOARD SYNC (FB-98) =====================

  handleClick(event) {
    const t = event.target
    if (!t || !t.closest) return

    // Sync panel index on panel click.
    const panel = t.closest('[data-tui-cursor-target="panel"]')
    if (panel) {
      const panelIdx = this.panelTargets.indexOf(panel)
      if (panelIdx !== -1 && panelIdx !== this.focusedIndex) {
        this.focusedIndex = panelIdx
        this.rowIndex = 0
        this.subPanelIndex = 0
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
        this.applySubPanelFocus()
        this.emitFocusChange()
      }
    }

    // Sync row index on row click (excluding clicks that originate from
    // the row's own checkbox — that's a checkbox toggle, not a row pick,
    // and the click still bubbles so we can update rowIndex on the row).
    const row = t.closest('[data-tui-cursor-target="row"]')
    if (row) {
      const rows = this.rowsInFocusedPanel()
      const rowIdx = rows.indexOf(row)
      if (rowIdx !== -1 && rowIdx !== this.rowIndex) {
        this.rowIndex = rowIdx
        this.applyRowFocus()
      }
    }
  }

  // ===================== INSERT FROM `i` =====================

  enterInsertFromFocus() {
    // Try, in order: focused row's first input, focused sub-panel's
    // first input, focused panel's first input. First hit wins.
    const candidates = []
    const row = this.focusedRow()
    if (row) candidates.push(row)
    const subs = this.subPanelsInFocusedPanel()
    if (subs[this.subPanelIndex]) candidates.push(subs[this.subPanelIndex])
    const panel = this.panelTargets[this.focusedIndex]
    if (panel) candidates.push(panel)
    for (const c of candidates) {
      const input = c.querySelector(INPUT_SELECTOR)
      if (input) {
        input.focus()
        // focusin listener will flip mode for us — but flip it now too
        // in case focus() raced.
        this.enterInsertMode()
        return true
      }
    }
    return false
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
