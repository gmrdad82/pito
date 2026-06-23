// pito--games-search
//
// Mounted on the `[data-controller="pito--games-search"]` element that the
// IGDB import sidebar injects into #pito-sidebar.
//
// BEHAVIOUR
//   - On connect(): auto-focus the search input; if prefill is non-empty,
//     select() so the user can type immediately to replace, and fire an
//     immediate search (no debounce delay for the pre-filled query).
//   - On input events: debounce 250ms + AbortController to cancel stale requests.
//   - Shows .pito-shimmer row while waiting for IGDB (search + import).
//   - Renders results as .pito-igdb-row elements inside the results target.
//     Each row has a small SQUARE cover-art thumbnail (t_thumb → t_cover_small).
//   - ↑ / ↓ moves highlight through rows.
//   - Enter on a highlighted row sends POST /games/import with the igdb_id +
//     title + conversation UUID. The sidebar is NOT cleared — instead the
//     results region is replaced with 5 step rows that shimmer while the job
//     broadcasts step completions back via Turbo Stream.
//   - Escape: handled by pito--resume's capture-phase listener (clears sidebar).
//
// DOM contract (set by GamesImport::Component ERB):
//   Controller: pito--games-search  on  .flex.flex-col wrapper
//   Values:     conversation-uuid (String), prefill (String),
//               i18n-searching (String), i18n-no-results (String),
//               i18n-error (String), i18n-in-library (String),
//               i18n-in-library-hint (String),
//               i18n-step-labels (Array) — JSON array of 5 step label strings
//   Targets:    input   — <input type="text">
//               shimmer — <p> for shimmer loading indicator (dots row)
//               status  — <p> for witty status text (no-results / error)
//               results — <div> container for result rows / step rows
//
// Auto-registered via eagerLoadControllersFrom.

import { Controller } from "@hotwired/stimulus"
import { paletteOpen } from "pito/settings"

const DEBOUNCE_MS   = 250
const HIGHLIGHT_CLS = "pito-resume-highlight"

// Per-step shimmer animation-delay offsets (stagger).  No new CSS needed —
// we inject inline animation-delay on each .pito-shimmer span so each step
// starts its sweep at a different phase.
const STEP_DELAYS = ["0s", "0.15s", "0.30s", "0.45s", "0.60s"]

export default class extends Controller {
  static targets = ["input", "shimmer", "status", "results"]
  static values  = {
    conversationUuid:    String,
    prefill:             { type: String, default: "" },
    i18nSearching:       { type: String, default: "" },
    i18nNoResults:       { type: String, default: "" },
    i18nError:           { type: String, default: "" },
    i18nInLibrary:       { type: String, default: "" },
    i18nInLibraryHint:   { type: String, default: "" },
    i18nStepLabels:      { type: Array,  default: [] },
  }

  connect() {
    this._timer       = null
    this._abort       = null
    this._requestId   = 0
    this._highlightIdx = -1

    // Listen for keydown on document so ↑/↓/Enter work even when the
    // input doesn't have focus (e.g. after clicking a row).
    this._onKey = this.#onKey.bind(this)
    document.addEventListener("keydown", this._onKey)

    // Wire input → debounced search
    this.inputTarget.addEventListener("input", this.#onInput.bind(this))

    // Prefill: trigger an immediate search if there's a preset query.
    const pre = this.prefillValue.trim()
    if (pre.length > 0) {
      this.inputTarget.value = pre
      this.#doSearch(pre)
    }

    // Auto-focus on spawn; requestAnimationFrame defers until the sidebar
    // is fully painted so the focus isn't swallowed by any transition.
    requestAnimationFrame(() => {
      this.inputTarget.focus()
      // Select prefilled text so the user can replace it by typing.
      if (pre.length > 0) this.inputTarget.select()
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
    this.#cancelPending()
  }

  // ── Private ────────────────────────────────────────────────────────────────

  #onInput() {
    const q = this.inputTarget.value.trim()
    this.#cancelPending()

    if (q.length === 0) {
      this.#setStatus("")
      this.#hideShimmer()
      this.resultsTarget.innerHTML = ""
      this._highlightIdx = -1
      return
    }

    this._timer = setTimeout(() => {
      this._timer = null
      this.#doSearch(q)
    }, DEBOUNCE_MS)
  }

  async #doSearch(query) {
    this.#showShimmer()
    this.#setStatus("")
    this.resultsTarget.innerHTML = ""
    this._highlightIdx = -1

    const myId = ++this._requestId
    const abort = new AbortController()
    this._abort = abort

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const resp = await fetch("/games/search", {
        method:  "POST",
        signal:  abort.signal,
        headers: {
          "Content-Type": "application/json",
          "Accept":       "application/json",
          ...(csrf ? { "X-CSRF-Token": csrf } : {}),
        },
        body: JSON.stringify({ query }),
      })

      if (myId !== this._requestId) return
      this.#hideShimmer()

      if (!resp.ok) {
        this.#setStatus(this.i18nErrorValue || "IGDB search failed.")
        return
      }

      const data = await resp.json()
      if (myId !== this._requestId) return

      if (data.error) {
        this.#setStatus(this.i18nErrorValue || "IGDB search failed.")
        return
      }

      const hits = data.hits || []
      if (hits.length === 0) {
        this.#setStatus(this.i18nNoResultsValue || "No results.")
        return
      }

      this.#setStatus("")
      this.#renderResults(hits, data.library_ids || [])

      // Highlight first row automatically.
      this._highlightIdx = 0
      this.#paintHighlight()
    } catch (err) {
      if (err.name !== "AbortError" && myId === this._requestId) {
        this.#hideShimmer()
        this.#setStatus(this.i18nErrorValue || "IGDB search failed.")
      }
    }
  }

  #renderResults(hits, libraryIds) {
    const container = this.resultsTarget
    container.innerHTML = ""

    hits.forEach((hit) => {
      const igdbId   = hit.id ?? hit["id"]
      const title    = hit.name ?? hit["name"] ?? ""
      const inLib    = libraryIds.includes(igdbId)
      const imageId  = hit.cover?.image_id ?? hit["cover"]?.["image_id"] ?? null

      const row = document.createElement("div")
      row.className     = "pito-igdb-row flex gap-2 items-center py-1 px-2 rounded cursor-pointer hover:bg-bg-hover"
      row.dataset.igdbId = String(igdbId)
      row.dataset.title  = title

      // Cover thumbnail — SQUARE (t_cover_small = 90×90).
      // Build the URL from the IGDB image_id (small square).
      if (imageId) {
        const img = document.createElement("img")
        img.src    = `https://images.igdb.com/igdb/image/upload/t_cover_small/${imageId}.jpg`
        img.alt    = title
        img.width  = 32
        img.height = 32
        img.className = "object-cover shrink-0 rounded-sm"
        row.appendChild(img)
      } else {
        const ph = document.createElement("div")
        ph.className = "w-8 h-8 shrink-0 rounded-sm bg-bg-hover"
        row.appendChild(ph)
      }

      // Title + in-library badge
      const info = document.createElement("div")
      info.className = "flex flex-col min-w-0"

      const titleEl = document.createElement("span")
      titleEl.className   = "text-fg truncate text-sm"
      titleEl.textContent = title
      info.appendChild(titleEl)

      // Re-release note — "(remake)" / "(remaster)" in cyan, stamped server-side
      // (Pito::Copy) so the original and its remake are distinguishable.
      const typeNote = hit.type_note ?? hit["type_note"]
      if (typeNote) {
        const note = document.createElement("span")
        note.className   = "text-xs text-cyan"
        note.textContent = typeNote
        info.appendChild(note)
      }

      if (inLib) {
        const badge = document.createElement("span")
        badge.className   = "text-xs text-accent"
        badge.textContent = (this.i18nInLibraryValue || "In Library") + " " + (this.i18nInLibraryHintValue || "(will resync)")
        info.appendChild(badge)
      }

      row.appendChild(info)

      // Click to select
      row.addEventListener("click", () => {
        const rows = this.#rows()
        this._highlightIdx = rows.indexOf(row)
        this.#paintHighlight()
        this.#selectHighlighted()
      })

      container.appendChild(row)
    })
  }

  #onKey(e) {
    if (paletteOpen()) return // command palette owns the keys while open (no dual cursor)
    const rows = this.#rows()

    if (e.key === "ArrowDown") {
      e.preventDefault()
      if (this._highlightIdx < rows.length - 1) {
        this._highlightIdx++
        this.#paintHighlight()
      }
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      if (this._highlightIdx > 0) {
        this._highlightIdx--
        this.#paintHighlight()
      }
    } else if (e.key === "Enter") {
      // Only intercept if we have a highlighted row; otherwise let the
      // chatbox form submit normally.
      if (rows.length > 0 && this._highlightIdx >= 0) {
        e.preventDefault()
        this.#selectHighlighted()
      }
    }
  }

  #selectHighlighted() {
    const rows = this.#rows()
    const row  = rows[this._highlightIdx]
    if (!row) return

    const igdbId = row.dataset.igdbId
    const title  = row.dataset.title
    if (!igdbId) return

    this.#importGame(igdbId, title)
  }

  // When a game is selected, replace the results region with 5 shimmer
  // step rows and keep the sidebar open.  The job broadcasts Turbo Stream
  // `replace` actions targeting each `import-step-N` DOM id.
  async #importGame(igdbId, title) {
    // Disable input + hide status; show step rows in results region.
    this.inputTarget.disabled = true
    this.inputTarget.classList.add("opacity-50")
    this.#setStatus("")
    this.#hideShimmer()
    this.#renderStepRows()

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const uuid = this.conversationUuidValue

    try {
      await fetch("/games/import", {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept":       "application/json",
          ...(csrf ? { "X-CSRF-Token": csrf } : {}),
        },
        body: JSON.stringify({ igdb_id: igdbId, title, uuid }),
      })
      // The job broadcasts step updates + messages over ActionCable.
      // The sidebar stays open; Esc closes it when done.
    } catch (_err) {
      // Network failure — swallow; job will not run.
    }
  }

  // Render 5 shimmer step rows into the results region.
  // Each row has a stable id="import-step-N" so Turbo Stream replace can
  // update them as the job completes each step.
  #renderStepRows() {
    const container = this.resultsTarget
    container.innerHTML = ""

    this.i18nStepLabelsValue.forEach((label, i) => {
      const step = i + 1
      const delay = STEP_DELAYS[i] || "0s"

      const row = document.createElement("div")
      row.id        = `import-step-${step}`
      row.className = "flex items-center gap-2 py-1 px-2 text-sm"

      // Shimmer dot — reuses .pito-shimmer; stagger via inline animation-delay.
      const dot = document.createElement("span")
      dot.className = "pito-shimmer shrink-0"
      dot.style.animationDelay = delay
      dot.textContent = "●"
      row.appendChild(dot)

      // Step label text — shimmers too, in sync with the dot (same per-row
      // delay) so the whole row pulses together, staggered against other rows.
      const lbl = document.createElement("span")
      lbl.className          = "pito-shimmer"
      lbl.style.animationDelay = delay
      lbl.textContent        = label
      row.appendChild(lbl)

      container.appendChild(row)
    })
  }

  #rows() {
    return Array.from(this.resultsTarget.querySelectorAll(".pito-igdb-row"))
  }

  #paintHighlight() {
    this.#rows().forEach((r, i) => r.classList.toggle(HIGHLIGHT_CLS, i === this._highlightIdx))
    const focused = this.#rows()[this._highlightIdx]
    if (focused && typeof focused.scrollIntoView === "function") {
      focused.scrollIntoView({ block: "nearest" })
    }
  }

  #showShimmer() {
    this.shimmerTarget.classList.remove("hidden")
  }

  #hideShimmer() {
    this.shimmerTarget.classList.add("hidden")
  }

  #setStatus(msg) {
    const el = this.statusTarget
    el.textContent = msg
    el.classList.toggle("hidden", !msg)
  }

  #cancelPending() {
    if (this._timer !== null) {
      clearTimeout(this._timer)
      this._timer = null
    }
    if (this._abort) {
      this._abort.abort()
      this._abort = null
    }
    this._requestId++
  }
}
