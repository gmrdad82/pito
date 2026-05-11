import { Controller } from "@hotwired/stimulus"

// Phase 7.5 — Step 04. Global keyboard shortcuts.
//
// Mirrors the `pito` CLI keymap (`extras/cli/src/keys.rs`) per locked
// decision Q6 (strict mirror). The CLI is the source of truth; this
// controller follows.
//
// Bindings:
//   Global
//     ?           toggle help dialog
//     t           toggle theme (handled by theme_controller — we still
//                 surface it in the help dialog). Was `n` pre-redesign.
//     /           open the global search modal (`#global-search-modal`)
//     i           open the IGDB-search modal (`#igdb-search-modal`)
//     Esc         close any open dialog / clear pending prefix
//   Navigation (`g` prefix, ~1s timeout)
//     g d         /            (dashboard)
//     g c         /channels
//     g v         /videos
//     g s         /saved_views
//     g e         /settings
//   Filter (`f` prefix, ~1s timeout)
//     f s         click the [starred]   filter chip on the current page
//   List rows (j/k highlight, space/s/D/Y) — best-effort:
//     j / k       move highlight down / up among `[data-keyboard-row]` elements
//     space       toggle the highlighted row's selection checkbox
//     s           click the highlighted row's `[data-keyboard-action="star"]` link
//     D           navigate to /deletions/:type/:ids (bulk selection or highlighted id)
//     Y           navigate to /syncs/:type/:ids
//   Tile / grid surfaces (games, bundles):
//     The container carries `data-keyboard-grid="true"` and each tile
//     carries `data-keyboard-tile`. `j` / `k` move vertically between
//     visual rows of tiles (computed by `getBoundingClientRect().top`);
//     `h` / `l` step one tile left/right inside the active row. When
//     no tile is highlighted, `j` / `l` pick the first tile and `k` /
//     `h` pick the last. The same `keyboard-highlight` class is used
//     so the visual treatment matches list rows.
//   Calendar month grid (`/calendar/month/...`):
//     Container carries `data-keyboard-grid="calendar-month"` and each
//     cell carries `data-keyboard-grid-cell`. The cell order is the
//     7-column Monday-first grid (left-to-right, top-to-bottom).
//     `j` / `k` jump one week (±7 cells), `h` / `l` step one day (±1
//     cell). Out-of-bounds moves are clamped to the grid extents.
//   Detail pages
//     v           open `data-keyboard-external-url` in a new tab
//     s / Y / D   click the analog action link in the page chrome
//   Action confirmation page
//     y           submit the action form
//     Esc / other clicks the [cancel] link
//
// Bindings are gated when focus sits inside `<input>`, `<textarea>`,
// `<select>`, or `[contenteditable]`, mirroring the CLI's "search
// overlay swallows keys" rule.
//
// Implementation notes:
// - Prefix state machine carries `pendingPrefix` (`null`, `"g"`, `"f"`)
//   with a 1000ms timeout so abandoned prefixes don't strand the user.
// - The controller is attached to `<body>` via `data-controller="keyboard"`
//   and adds a single document-level `keydown` listener.
// - The dialog target is the help overlay; `showModal()` /  `close()`
//   open and close it.
export default class extends Controller {
  static targets = ["dialog"]

  static PREFIX_TIMEOUT_MS = 1000

  connect() {
    this.pendingPrefix = null
    this.prefixTimer = null
    // 2026-05-11 — install-level master toggle. The layout renders
    // `data-keyboard-navigation-enabled="yes|no"` on `<body>` (yes/no
    // strings per the project's external-boolean rule). When the value
    // is "no" we skip registering the global keydown listener entirely
    // so per-row hotkeys (j/k, s, D, Y…) and the `?` help shortcut go
    // silent. `openHelp` (the [_] footer affordance) intentionally
    // ignores the toggle — keyboard-off users can still click it to
    // browse the shortcut catalogue.
    this.disabled = this.element.dataset.keyboardNavigationEnabled === "no"
    if (this.disabled) return
    this.boundKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    if (this.boundKeydown) {
      document.removeEventListener("keydown", this.boundKeydown)
    }
    this.clearPrefix()
  }

  // Public: open the help dialog. Wired to the visible `[ ? ]` link
  // via `data-action="click->keyboard#openHelp"`. The action is
  // explicitly exempt from the master toggle — even when keyboard
  // navigation is disabled, the bracketed `[_]` affordance opens the
  // shortcut catalogue so the surface stays discoverable.
  openHelp(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  clickOutside(event) {
    if (this.hasDialogTarget && event.target === this.dialogTarget) {
      this.dialogTarget.close()
    }
  }

  onKeydown(event) {
    // Hard guard: never intercept while typing.
    if (this.isEditableTarget(event.target)) return

    // Browser-native shortcuts always pass through. We never bind on a
    // modifier key — `Ctrl+F`, `Cmd+K`, etc. stay native.
    if (event.metaKey || event.ctrlKey || event.altKey) return

    // Esc handling: cancel pending prefix, close dialog, then page
    // semantics (action-screen cancel link).
    if (event.key === "Escape") {
      if (this.pendingPrefix) {
        this.clearPrefix()
        event.preventDefault()
        return
      }
      if (this.hasDialogTarget && this.dialogTarget.open) {
        this.dialogTarget.close()
        event.preventDefault()
        return
      }
      if (this.handleActionScreenCancel()) {
        event.preventDefault()
        return
      }
      return
    }

    // If a dialog is open, only `?` (toggle) and Esc (above) are bound.
    // Let the rest pass through so `<dialog>` semantics stay intact.
    if (this.hasDialogTarget && this.dialogTarget.open) {
      if (event.key === "?") {
        event.preventDefault()
        this.dialogTarget.close()
      }
      return
    }

    // Prefix-second-key dispatch.
    if (this.pendingPrefix === "g") {
      this.clearPrefix()
      this.handleGPrefix(event)
      return
    }
    if (this.pendingPrefix === "f") {
      this.clearPrefix()
      this.handleFPrefix(event)
      return
    }

    // Action confirmation page: `y` submits, anything else falls through
    // to the generic handlers (Esc handled above). The page is detected
    // by the presence of an opt-in `data-keyboard-confirmation` form.
    if (event.key === "y" && this.handleActionScreenConfirm()) {
      event.preventDefault()
      return
    }

    // Single-key bindings.
    switch (event.key) {
      case "?":
        event.preventDefault()
        if (this.hasDialogTarget) this.dialogTarget.showModal()
        return
      case "/":
        if (this.openGlobalSearch()) event.preventDefault()
        return
      case "i":
        if (this.openIgdbSearch()) event.preventDefault()
        return
      case "g":
        this.beginPrefix("g")
        event.preventDefault()
        return
      case "f":
        this.beginPrefix("f")
        event.preventDefault()
        return
      case "j":
        if (this.moveHighlightVertical(1)) event.preventDefault()
        return
      case "k":
        if (this.moveHighlightVertical(-1)) event.preventDefault()
        return
      case "h":
        if (this.moveHighlightHorizontal(-1)) event.preventDefault()
        return
      case "l":
        if (this.moveHighlightHorizontal(1)) event.preventDefault()
        return
      case " ":
        if (this.toggleHighlightedCheckbox()) event.preventDefault()
        return
      case "s":
        if (this.clickRowOrPageAction("star")) event.preventDefault()
        return
      case "v":
        if (this.openExternalUrl()) event.preventDefault()
        return
      case "D":
        if (this.navigateBulk("delete")) event.preventDefault()
        return
      case "Y":
        if (this.navigateBulk("sync")) event.preventDefault()
        return
    }
  }

  // ---------- prefix state ----------

  beginPrefix(prefix) {
    this.pendingPrefix = prefix
    if (this.prefixTimer) clearTimeout(this.prefixTimer)
    this.prefixTimer = setTimeout(() => this.clearPrefix(), this.constructor.PREFIX_TIMEOUT_MS)
  }

  clearPrefix() {
    this.pendingPrefix = null
    if (this.prefixTimer) {
      clearTimeout(this.prefixTimer)
      this.prefixTimer = null
    }
  }

  handleGPrefix(event) {
    const map = { d: "/", c: "/channels", v: "/videos", s: "/saved_views", e: "/settings" }
    const path = map[event.key]
    if (path) {
      event.preventDefault()
      window.location.assign(path)
    }
  }

  handleFPrefix(event) {
    const map = { s: "starred" }
    const param = map[event.key]
    if (!param) return
    // Click the matching filter chip on the current page if one is rendered.
    const chip = document.querySelector(
      `[data-keyboard-filter-chip="${param}"], [data-filter-chip="${param}"] a, .filter-chip[data-param="${param}"] a`
    )
    if (chip) {
      event.preventDefault()
      chip.click()
    }
  }

  // ---------- helpers ----------

  isEditableTarget(target) {
    if (!target || !target.matches) return false
    return target.matches("input, textarea, select, [contenteditable], [contenteditable='true']")
  }

  // Phase 14 §1 polish — `/` opens the global search modal
  // (`shared/_search_modal`). The inline navbar search input it
  // used to focus was retired in the same dispatch. Returning
  // `false` from here lets the keystroke fall through (e.g. into
  // an open page-local search input) instead of swallowing it.
  openGlobalSearch() {
    return this.openLayoutDialog("global-search-modal", "global-search-modal")
  }

  // Phase 14 §1 polish — `i` opens the IGDB-search modal
  // (`shared/_igdb_search_modal`). Same shape as `/` above:
  // returning `false` lets the keystroke pass through if the
  // dialog isn't on the page (older or stripped layouts).
  openIgdbSearch() {
    return this.openLayoutDialog("igdb-search-modal", "igdb-search-modal")
  }

  // Resolves the layout-level <dialog> by id, looks up its
  // controller via `window.Stimulus`, and calls `open()`. Falls
  // back to a direct `showModal()` if the controller isn't wired.
  // Returns true when a dialog was opened, false otherwise.
  openLayoutDialog(elementId, controllerIdentifier) {
    const dialog = document.getElementById(elementId)
    if (!dialog) return false
    const app = window.Stimulus
    if (app && typeof app.getControllerForElementAndIdentifier === "function") {
      const ctrl = app.getControllerForElementAndIdentifier(dialog, controllerIdentifier)
      if (ctrl && typeof ctrl.open === "function") {
        ctrl.open()
        return true
      }
    }
    if (typeof dialog.showModal === "function") {
      dialog.showModal()
      return true
    }
    return false
  }

  // ---------- list-row highlight ----------
  //
  // A page opts in by tagging its row container with
  // `data-keyboard-rows` and each row with `data-keyboard-row`. The
  // controller adds a `keyboard-highlight` class to the active row.

  rowElements() {
    return Array.from(document.querySelectorAll("[data-keyboard-row]"))
  }

  highlightedRow() {
    return document.querySelector("[data-keyboard-row].keyboard-highlight")
  }

  moveHighlight(delta) {
    const rows = this.rowElements()
    if (rows.length === 0) return false
    const current = this.highlightedRow()
    let nextIndex
    if (!current) {
      nextIndex = delta > 0 ? 0 : rows.length - 1
    } else {
      const currentIndex = rows.indexOf(current)
      nextIndex = currentIndex + delta
      if (nextIndex < 0) nextIndex = 0
      if (nextIndex > rows.length - 1) nextIndex = rows.length - 1
      current.classList.remove("keyboard-highlight")
    }
    rows[nextIndex].classList.add("keyboard-highlight")
    rows[nextIndex].scrollIntoView({ block: "nearest" })
    return true
  }

  // ---------- grid / tile highlight ----------
  //
  // A page opts in by tagging its container with `data-keyboard-grid`.
  //
  //   data-keyboard-grid="true"
  //     Plain tile grid (e.g. /games, /bundles). Each tile carries
  //     `data-keyboard-tile`. `j`/`k` jump to the nearest tile in the
  //     next/previous visual row (rows computed from bounding-rect
  //     `top` values); `h`/`l` step one tile within the active row.
  //
  //   data-keyboard-grid="calendar-month"
  //     Monday-first 7-column calendar grid (/calendar/month/...).
  //     Each cell carries `data-keyboard-grid-cell`. `j`/`k` jump a
  //     full week (±7 cells); `h`/`l` step a day (±1 cell). All moves
  //     are clamped to the rendered grid.
  //
  // `j`/`k` route through `moveHighlightVertical`; `h`/`l` through
  // `moveHighlightHorizontal`. When no grid is on the page the
  // dispatcher falls back to the row-based `moveHighlight` so list
  // pages keep their existing behaviour. Calling `moveHighlightHorizontal`
  // outside a grid surface deliberately no-ops (`h`/`l` were never
  // bound on list pages).

  gridContainer() {
    return document.querySelector("[data-keyboard-grid]")
  }

  gridKind() {
    const container = this.gridContainer()
    if (!container) return null
    const value = container.getAttribute("data-keyboard-grid")
    if (value === "calendar-month") return "calendar-month"
    return "tiles"
  }

  gridCells() {
    const container = this.gridContainer()
    if (!container) return []
    const selector =
      this.gridKind() === "calendar-month"
        ? "[data-keyboard-grid-cell]"
        : "[data-keyboard-tile]"
    return Array.from(container.querySelectorAll(selector))
  }

  highlightedGridCell() {
    const container = this.gridContainer()
    if (!container) return null
    return container.querySelector(
      "[data-keyboard-tile].keyboard-highlight, [data-keyboard-grid-cell].keyboard-highlight"
    )
  }

  // j / k. Grid-aware: prefers grid surfaces over `[data-keyboard-row]`
  // when the page declares both (no current surface does, but we want
  // the dispatch to be predictable).
  moveHighlightVertical(delta) {
    if (this.gridContainer()) {
      return this.moveGrid(delta, 0)
    }
    return this.moveHighlight(delta)
  }

  // h / l. Only meaningful inside a grid surface. Returns false outside
  // one so the keystroke falls through (the controller never preventDefaults).
  moveHighlightHorizontal(delta) {
    if (this.gridContainer()) {
      return this.moveGrid(0, delta)
    }
    return false
  }

  moveGrid(deltaY, deltaX) {
    const kind = this.gridKind()
    if (kind === "calendar-month") {
      return this.moveCalendarMonth(deltaY, deltaX)
    }
    return this.moveTileGrid(deltaY, deltaX)
  }

  // Plain tile grid (games, bundles). Rows are derived from each tile's
  // `getBoundingClientRect().top` — tiles whose tops differ by less than
  // `ROW_EPSILON_PX` belong to the same row. The next/prev row is then
  // the set of tiles immediately above / below the active one; we pick
  // the tile in that row whose horizontal centre is nearest to the
  // active tile's centre.
  moveTileGrid(deltaY, deltaX) {
    const tiles = this.gridCells()
    if (tiles.length === 0) return false

    const current = this.highlightedGridCell()
    if (!current) {
      // First press: pick the first tile when moving forward (`j` / `l`),
      // the last when moving backward (`k` / `h`).
      const target = deltaY > 0 || deltaX > 0 ? tiles[0] : tiles[tiles.length - 1]
      target.classList.add("keyboard-highlight")
      target.scrollIntoView({ block: "nearest" })
      return true
    }

    // Build visual rows.
    const rows = this.groupTilesIntoRows(tiles)
    const currentRowIndex = rows.findIndex((row) => row.includes(current))
    if (currentRowIndex === -1) return false
    const currentRow = rows[currentRowIndex]
    const currentRect = current.getBoundingClientRect()
    const currentCx = currentRect.left + currentRect.width / 2

    let target = null
    if (deltaY !== 0) {
      const nextRowIndex = currentRowIndex + deltaY
      if (nextRowIndex < 0 || nextRowIndex >= rows.length) return false
      target = this.nearestTileByX(rows[nextRowIndex], currentCx)
    } else if (deltaX !== 0) {
      const currentIdxInRow = currentRow.indexOf(current)
      const nextIdxInRow = currentIdxInRow + deltaX
      if (nextIdxInRow < 0 || nextIdxInRow >= currentRow.length) return false
      target = currentRow[nextIdxInRow]
    }

    if (!target) return false
    current.classList.remove("keyboard-highlight")
    target.classList.add("keyboard-highlight")
    target.scrollIntoView({ block: "nearest" })
    return true
  }

  groupTilesIntoRows(tiles) {
    const ROW_EPSILON_PX = 4
    const sorted = tiles
      .map((tile) => ({ tile, top: tile.getBoundingClientRect().top, left: tile.getBoundingClientRect().left }))
      .sort((a, b) => {
        if (Math.abs(a.top - b.top) < ROW_EPSILON_PX) return a.left - b.left
        return a.top - b.top
      })
    const rows = []
    let currentRow = []
    let currentTop = null
    for (const entry of sorted) {
      if (currentTop === null) {
        currentRow.push(entry.tile)
        currentTop = entry.top
      } else if (Math.abs(entry.top - currentTop) < ROW_EPSILON_PX) {
        currentRow.push(entry.tile)
      } else {
        rows.push(currentRow)
        currentRow = [entry.tile]
        currentTop = entry.top
      }
    }
    if (currentRow.length > 0) rows.push(currentRow)
    return rows
  }

  nearestTileByX(row, targetCx) {
    let best = null
    let bestDistance = Infinity
    for (const tile of row) {
      const rect = tile.getBoundingClientRect()
      const cx = rect.left + rect.width / 2
      const distance = Math.abs(cx - targetCx)
      if (distance < bestDistance) {
        bestDistance = distance
        best = tile
      }
    }
    return best
  }

  // Calendar month grid (`/calendar/month/...`). The cell order matches
  // the rendered grid (Monday-first, left-to-right, top-to-bottom); the
  // grid is always a multiple of 7. `j`/`k` shift ±7, `h`/`l` shift ±1.
  // All moves clamp to the rendered cell range.
  moveCalendarMonth(deltaY, deltaX) {
    const cells = this.gridCells()
    if (cells.length === 0) return false

    const current = this.highlightedGridCell()
    if (!current) {
      // First press: prefer today's cell if it's still in the grid; fall
      // back to the first (or last on negative delta) cell.
      const today = cells.find((cell) => cell.classList.contains("today"))
      const fallback = deltaY > 0 || deltaX > 0 ? cells[0] : cells[cells.length - 1]
      const target = today || fallback
      target.classList.add("keyboard-highlight")
      target.scrollIntoView({ block: "nearest" })
      return true
    }

    const currentIndex = cells.indexOf(current)
    if (currentIndex === -1) return false

    const shift = deltaY * 7 + deltaX
    const nextIndex = currentIndex + shift
    if (nextIndex < 0 || nextIndex >= cells.length) return false

    current.classList.remove("keyboard-highlight")
    cells[nextIndex].classList.add("keyboard-highlight")
    cells[nextIndex].scrollIntoView({ block: "nearest" })
    return true
  }

  toggleHighlightedCheckbox() {
    const row = this.highlightedRow()
    if (!row) return false
    const checkbox = row.querySelector('input[type="checkbox"]')
    if (!checkbox || checkbox.disabled || checkbox.hidden) return false
    checkbox.click()
    return true
  }

  // ---------- per-row / per-page actions ----------

  clickPageAction(action) {
    const target = document.querySelector(`[data-keyboard-page-action="${action}"]`)
    if (!target) return false
    target.click()
    return true
  }

  clickRowOrPageAction(action) {
    const row = this.highlightedRow()
    if (row) {
      const rowAction = row.querySelector(`[data-keyboard-action="${action}"]`)
      if (rowAction) {
        rowAction.click()
        return true
      }
    }
    return this.clickPageAction(action)
  }

  openExternalUrl() {
    const node =
      this.highlightedRow()?.querySelector("[data-keyboard-external-url]") ||
      document.querySelector("[data-keyboard-external-url]")
    if (!node) return false
    const url = node.getAttribute("data-keyboard-external-url")
    if (!url) return false
    window.open(url, "_blank", "noopener,noreferrer")
    return true
  }

  navigateBulk(kind) {
    // bulk selection (one or more rows checked) takes priority, falling
    // back to the highlighted row's id and finally a page-level action.
    const ids = this.bulkSelectedIds()
    const type = this.recordType()
    if (ids.length > 0 && type) {
      const path = kind === "delete" ? `/deletions/${type}/${ids.join(",")}` : `/syncs/${type}/${ids.join(",")}`
      window.location.assign(path)
      return true
    }
    const row = this.highlightedRow()
    if (row && type) {
      const id = row.getAttribute("data-keyboard-row-id")
      if (id) {
        const path = kind === "delete" ? `/deletions/${type}/${id}` : `/syncs/${type}/${id}`
        window.location.assign(path)
        return true
      }
    }
    return this.clickPageAction(kind)
  }

  bulkSelectedIds() {
    const rows = this.rowElements()
    const ids = []
    rows.forEach((r) => {
      const checkbox = r.querySelector('input[type="checkbox"]')
      if (checkbox && checkbox.checked && !checkbox.disabled) {
        const value = r.getAttribute("data-keyboard-row-id") || checkbox.value
        if (value) ids.push(value)
      }
    })
    return ids
  }

  recordType() {
    const node = document.querySelector("[data-keyboard-record-type]")
    return node ? node.getAttribute("data-keyboard-record-type") : null
  }

  // ---------- action confirmation page ----------

  handleActionScreenConfirm() {
    const form = document.querySelector("form[data-keyboard-confirmation]")
    if (!form) return false
    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
    return true
  }

  handleActionScreenCancel() {
    const cancel = document.querySelector("[data-keyboard-confirmation-cancel]")
    if (!cancel) return false
    if (cancel instanceof HTMLAnchorElement) {
      window.location.assign(cancel.href)
    } else {
      cancel.click()
    }
    return true
  }
}
