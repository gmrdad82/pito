// Phase 27 v2 spec 06 — `games-filter` Stimulus controller.
//
// Intercepts filter-chip clicks on `/games`. Responsibilities:
//
//   1. Flip the clicked chip's checked state in-place (rewrites the
//      bracketed indicator `[ ]` ↔ `[x]` and toggles the `chip--active`
//      CSS class).
//   2. Apply the `played` cascade (check-only, NOT symmetric) — when
//      the clicked chip is `played` AND we're CHECKING it, also force-
//      check `released` + `owned` and force-check every platform chip
//      if NONE were checked. Un-checking `played` does NOT release the
//      implied chips.
//   3. Compute the new checked-token set from the post-flip DOM.
//   4. Build the canonical URL (`/games` when every chip is checked,
//      `/games?filters=<csv>` otherwise) and update the browser URL
//      via `history.replaceState` so back/forward + bookmarks work
//      without a full page navigation.
//   5. Point the `games_listing` Turbo Frame's `src` at the new URL
//      so Turbo re-fetches just the listing partition.
//
// JS-off fallback: every chip's anchor `href` already points at the
// post-toggle URL (computed server-side in the FilterChipComponent),
// so JS-off users get the correct page on click with a full
// navigation. The Stimulus controller is purely a no-reload UX
// upgrade.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chip"]
  static values = {
    universe:    Array,   // every valid token in render order
    requestPath: String,  // typically "/games"
    frameId:     String   // typically "games_listing"
  }

  // The platform group — used by the `played` cascade to know which
  // chips to force-check when at least one of them isn't already
  // checked. Mirrors the helper's `PLATFORM_TOKENS` constant.
  //
  // Phase 27 v2 spec 06 (2026-05-17 PC store collapse): `gog` + `epic`
  // were retired; PC = Steam everywhere.
  static PLATFORM_TOKENS = ["ps5", "switch2", "steam"]

  toggle(event) {
    event.preventDefault()

    const chip   = event.currentTarget
    const token  = chip.dataset.filterToken
    const wasChecked = chip.classList.contains("chip--active")
    const willCheck  = !wasChecked

    // 1. Flip the clicked chip.
    this.setChipState(chip, willCheck)

    // 2. Apply the `played` cascade — check-only, not symmetric.
    //    The data-implied attribute carries `"released,owned"` for
    //    the played chip; we additionally check every platform chip
    //    if zero are currently checked.
    if (willCheck && token === "played") {
      const implied = (chip.dataset.implied || "")
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean)
      implied.forEach((impliedToken) => {
        const impliedChip = this.chipFor(impliedToken)
        if (impliedChip) this.setChipState(impliedChip, true)
      })

      // Force-check every platform chip if none are currently
      // checked. A played game must be on SOME platform; un-
      // checking every platform together with `played` is a
      // contradictory state we want to avoid by default.
      const platformChips = this.constructor.PLATFORM_TOKENS
        .map((t) => this.chipFor(t))
        .filter(Boolean)
      const anyPlatformChecked = platformChips.some((c) =>
        c.classList.contains("chip--active")
      )
      if (!anyPlatformChecked) {
        platformChips.forEach((c) => this.setChipState(c, true))
      }
    }

    // 3. Compute the new checked-token set from the post-flip DOM.
    const checked = this.currentCheckedTokens()

    // 4. Build the canonical URL + push to history.
    const url = this.canonicalUrl(checked)
    window.history.replaceState(null, "", url)

    // 5. Refresh the Turbo Frame.
    const frame = document.getElementById(this.frameIdValue)
    if (frame) frame.src = url
  }

  // ---------- helpers ----------

  setChipState(chip, checked) {
    if (checked) {
      chip.classList.add("chip--active")
    } else {
      chip.classList.remove("chip--active")
    }
    const indicator = chip.querySelector(".md-check-static")
    if (indicator) indicator.textContent = checked ? "[x]" : "[ ]"
  }

  chipFor(token) {
    return this.chipTargets.find((c) => c.dataset.filterToken === token)
  }

  currentCheckedTokens() {
    // Preserve `universeValue` order so the CSV is stable across
    // requests; bookmarks survive.
    return this.universeValue.filter((token) => {
      const chip = this.chipFor(token)
      return chip && chip.classList.contains("chip--active")
    })
  }

  canonicalUrl(checked) {
    const path = this.requestPathValue || "/games"
    if (checked.length === this.universeValue.length) {
      // Every chip checked → emit the bare path. This is the single
      // canonical "full list" URL.
      return path
    }
    const csv = checked.join(",")
    return `${path}?filters=${csv}`
  }
}
