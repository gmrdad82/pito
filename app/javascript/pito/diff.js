// pito/diff.js
//
// Pure, theme-agnostic diff engine for the two-phase diff-reveal animation.
//
// Given a `from` string, a `to` string, and a granularity ("char" or "line"),
// computes the longest common prefix and suffix (in the chosen unit), leaving
// the differing middle split into:
//
//   • `removed` — the text that appears in `from` but not `to` (subtractions)
//   • `added`   — the text that appears in `to` but not `from` (additions)
//
// The controller uses these parts to drive a two-phase animation:
//   Step 1 — reverse-delete `removed` from each cell (shrink the middle)
//   Step 2 — type `added` into each cell (grow the middle)
//
// All functions are pure (no DOM, no side-effects) — easy to unit-test.
//
// Unit semantics
// --------------
//   "char" — each unit is a single UTF-16 character (String index / slice).
//   "line" — each unit is a newline-terminated line.  The split preserves the
//             trailing newline as part of each line so that join("") round-trips
//             exactly.  An empty string yields an empty array.
//
// Performance note: we use a simple O(n) prefix/suffix scan rather than a full
// LCS/Myers diff.  The strings we diff are short (theme list rows, quip lines),
// so the quadratic worst-case never matters.

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Split a string into the units for the given granularity.
 *
 * @param {string} text
 * @param {"char"|"line"} granularity
 * @returns {string[]}
 */
function toUnits(text, granularity) {
  if (granularity === "line") {
    if (text === "") return []
    // Split on newlines, keeping the newline at the end of each line so that
    // units.join("") === text (round-trip safe).
    return text.split(/(?<=\n)/)
  }
  // "char" — spread into individual characters (handles BMP; good enough for
  // theme names and quip strings which are all ASCII or Latin-1).
  return [...text]
}

/**
 * Join an array of units back into a string.
 *
 * @param {string[]} units
 * @returns {string}
 */
function fromUnits(units) {
  return units.join("")
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Compute the two-phase diff between `from` and `to` at `granularity`.
 *
 * Returns the four string pieces the controller needs:
 *
 *   prefix  — common leading text (unchanged, always visible)
 *   removed — `from`'s differing middle (reverse-delete this)
 *   added   — `to`'s differing middle   (type this)
 *   suffix  — common trailing text (unchanged, always visible)
 *
 * Invariants:
 *   prefix + removed + suffix === from   (exact round-trip)
 *   prefix + added  + suffix === to      (exact round-trip)
 *
 * When `from === to`, all four parts are returned correctly:
 *   prefix = from, removed = "", added = "", suffix = ""
 *
 * @param {string} from         Pre-transform text
 * @param {string} to           Post-transform text
 * @param {"char"|"line"} [granularity="char"]
 * @returns {{ prefix: string, removed: string, added: string, suffix: string }}
 */
export function diffParts(from, to, granularity = "char") {
  const fromUnitsArr = toUnits(from, granularity)
  const toUnitsArr   = toUnits(to,   granularity)

  const fLen = fromUnitsArr.length
  const tLen = toUnitsArr.length

  // --- common prefix ---
  let prefixLen = 0
  const maxPrefix = Math.min(fLen, tLen)
  while (prefixLen < maxPrefix && fromUnitsArr[prefixLen] === toUnitsArr[prefixLen]) {
    prefixLen++
  }

  // --- common suffix (don't overlap the prefix) ---
  let suffixLen = 0
  const maxSuffix = Math.min(fLen - prefixLen, tLen - prefixLen)
  while (
    suffixLen < maxSuffix &&
    fromUnitsArr[fLen - 1 - suffixLen] === toUnitsArr[tLen - 1 - suffixLen]
  ) {
    suffixLen++
  }

  const prefix  = fromUnits(fromUnitsArr.slice(0, prefixLen))
  const suffix  = suffixLen > 0 ? fromUnits(fromUnitsArr.slice(fLen - suffixLen)) : ""
  const removed = fromUnits(fromUnitsArr.slice(prefixLen, fLen - suffixLen))
  const added   = fromUnits(toUnitsArr.slice(prefixLen, tLen - suffixLen))

  return { prefix, removed, added, suffix }
}

/**
 * Render a cell's text given its fixed prefix/suffix and a mid string.
 *
 * Convenience used by the controller on every tick to build the textContent
 * for each cell.
 *
 *   renderCell(prefix, mid, suffix) → prefix + mid + suffix
 *
 * @param {string} prefix
 * @param {string} mid    Current (possibly partial) middle text
 * @param {string} suffix
 * @returns {string}
 */
export function renderCell(prefix, mid, suffix) {
  return prefix + mid + suffix
}

/**
 * Split a string into its units for the given granularity.
 *
 * Exported so the controller can advance by CHARS_TICK units per tick without
 * re-splitting on every frame.
 *
 * @param {string} text
 * @param {"char"|"line"} granularity
 * @returns {string[]}
 */
export function splitUnits(text, granularity) {
  return toUnits(text, granularity)
}
