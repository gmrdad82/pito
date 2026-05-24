// Phase 27 v2 spec 06 + ADR 0013 — `games-filter` Stimulus controller.
//
// Intercepts filter-chip clicks on `/games`. Responsibilities:
//
//   1. Flip the clicked chip's checked state in-place (rewrites the
//      bracketed indicator `[ ]` ↔ `[x]` and toggles the `chip--active`
//      CSS class).
//   2. Apply the CHECK cascade — when CHECKING a child chip, auto-
//      check each of its parents (e.g. checking `played` auto-checks
//      `released + owned`, and auto-checks every platform chip when
//      none are currently checked).
//   3. Apply the UNCHECK cascade (ADR 0013) — when UNCHECKING any
//      chip, walk dependents and auto-uncheck any whose parent
//      requirements are no longer satisfied. Cascades transitively
//      (uncheck `released` → uncheck `owned` → uncheck `played`).
//   4. Compute the new checked-token set from the post-cascade DOM.
//   5. Build the canonical URL (`/games` when every chip is checked,
//      `/games?filters=<csv>` otherwise) and update the browser URL
//      via `history.replaceState` so back/forward + bookmarks work
//      without a full page navigation.
//   6. Point the `games_listing` Turbo Frame's `src` at the new URL
//      so Turbo re-fetches just the listing partition.
//
// Cascade rules (ADR 0013):
//
//   - `owned`  requires `released`              (lifecycle dep)
//   - `played` requires `released + owned`      + ≥ 1 platform chip
//
// `not_owned + played` is CONDITIONALLY mutex — they may coexist iff
// `owned` is also checked (owned still satisfies played's ownership
// dep). When `owned` is unchecked, `played` auto-unchecks via the
// generic uncheck cascade because its `owned` parent is no longer met.
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
    universe:       Array,   // every valid token in render order
    defaultChecked: Array,   // bare-/games checked set (universe minus `played`)
    requestPath:    String,  // typically "/games"
    frameId:        String   // typically "games_listing"
  }

  // The platform group — used by the `played` cascade to know which
  // chips to force-check when at least one of them isn't already
  // checked. Mirrors the helper's `PLATFORM_TOKENS` constant.
  //
  // Phase 27 v2 spec 06 (2026-05-17 PC store collapse): `gog` + `epic`
  // were retired; PC = Steam everywhere.
  static PLATFORM_TOKENS = ["ps", "switch", "steam"]

  // Dependency map: child token → array of required parent tokens.
  // Platform requirement for `played` is handled separately because
  // it's "at least ONE of N" rather than "all of N".
  static DEPS = {
    owned:  ["released"],
    played: ["released", "owned"]
  }

  toggle(event) {
    event.preventDefault()

    const chip   = event.currentTarget
    const token  = chip.dataset.filterToken
    const wasChecked = chip.classList.contains("chip--active")
    const willCheck  = !wasChecked

    // 1. Flip the clicked chip.
    this.setChipState(chip, willCheck)

    // 2. CHECK cascade — auto-check parents when checking a child.
    if (willCheck) {
      this.cascadeCheckParents(token)
    }

    // 3. UNCHECK cascade — walk dependents until steady state.
    //    Idempotent: when checking a child, parents were just satisfied
    //    above, so nothing further changes here.
    this.enforceUncheckCascade()

    // 4. Compute the new checked-token set from the post-cascade DOM.
    const checked = this.currentCheckedTokens()

    // 5. Build the canonical URL + push to history.
    const url = this.canonicalUrl(checked)
    window.history.replaceState(null, "", url)

    // 6. Refresh the Turbo Frame.
    const frame = document.getElementById(this.frameIdValue)
    if (frame) frame.src = url
  }

  // ---------- cascade helpers ----------

  // CHECK cascade — checking a child forces its parents on.
  //
  // For `played`, parents are `released + owned` (per DEPS) PLUS the
  // "at least one platform chip" rule preserved from spec 06: if no
  // platform chip is currently checked, check all of them.
  cascadeCheckParents(token) {
    const parents = this.constructor.DEPS[token] || []
    parents.forEach((parentToken) => {
      const parentChip = this.chipFor(parentToken)
      if (parentChip) this.setChipState(parentChip, true)
    })

    if (token === "played") {
      const platformChips = this.platformChips()
      const anyPlatformChecked = platformChips.some((c) =>
        c.classList.contains("chip--active")
      )
      if (!anyPlatformChecked) {
        platformChips.forEach((c) => this.setChipState(c, true))
      }
    }
  }

  // UNCHECK cascade — corrective sweep that auto-unchecks any chip
  // whose dependencies are no longer satisfied. Repeats until no
  // changes (transitive: uncheck `released` → uncheck `owned` →
  // uncheck `played`).
  //
  // Safety bound: with three rules in DEPS the cascade reaches steady
  // state in ≤ 3 passes. We cap iterations at 5 defensively in case
  // DEPS grows in the future.
  enforceUncheckCascade() {
    const isChecked = (t) => {
      const c = this.chipFor(t)
      return !!(c && c.classList.contains("chip--active"))
    }

    let changed = true
    let safety  = 5
    while (changed && safety > 0) {
      changed = false
      safety -= 1

      for (const [child, parents] of Object.entries(this.constructor.DEPS)) {
        if (!isChecked(child)) continue
        if (parents.every(isChecked)) continue
        // Dependency unsatisfied — force-uncheck this child.
        const childChip = this.chipFor(child)
        if (childChip) {
          this.setChipState(childChip, false)
          changed = true
        }
      }

      // `played` also requires ≥ 1 platform chip checked. If `played`
      // is on but every platform chip is off, uncheck `played`.
      if (isChecked("played")) {
        const anyPlatform = this.platformChips().some((c) =>
          c.classList.contains("chip--active")
        )
        if (!anyPlatform) {
          const playedChip = this.chipFor("played")
          if (playedChip) {
            this.setChipState(playedChip, false)
            changed = true
          }
        }
      }
    }
  }

  // ---------- DOM helpers ----------

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

  platformChips() {
    return this.constructor.PLATFORM_TOKENS
      .map((t) => this.chipFor(t))
      .filter(Boolean)
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
    // User-locked 2026-05-17: bare `/games` corresponds to the
    // default-checked set (universe minus `played`), NOT to every
    // chip being checked. Adding `played` is an explicit opt-in
    // and must surface as `?filters=...,played` in the URL.
    if (this.matchesDefaultChecked(checked)) {
      return path
    }
    const csv = checked.join(",")
    return `${path}?filters=${csv}`
  }

  // True when the supplied checked-token array matches the
  // `defaultCheckedValue` set element-for-element (order does not
  // matter — `currentCheckedTokens` already emits universe order so
  // a plain length+includes compare is enough). When the Stimulus
  // controller renders without the value (legacy markup), we fall
  // back to the prior "every chip checked" rule so nothing breaks.
  matchesDefaultChecked(checked) {
    const defaults = this.hasDefaultCheckedValue ? this.defaultCheckedValue : this.universeValue
    if (checked.length !== defaults.length) return false
    return defaults.every((t) => checked.includes(t))
  }
}
