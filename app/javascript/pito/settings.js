// Reads sound/fx settings from the server-rendered element.
// The element is replaced via Turbo Stream when settings change.
// Fail-open: when the element or attribute is absent, treat sound/fx as enabled (true).

export function soundEnabled() {
  return document.getElementById("pito-settings")?.dataset.sound !== "false"
}

export function fxEnabled() {
  return document.getElementById("pito-settings")?.dataset.fx !== "false"
}

// True when decorative motion should be suppressed: either the user set
// `prefers-reduced-motion: reduce`, or fx is turned off via `/config fx off`.
// The canonical gate for blink/trail/animation theatrics. matchMedia is guarded
// for jsdom (some test envs leave it undefined).
export function motionDisabled() {
  const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
  return !!reduce || !fxEnabled()
}

// The chosen reveal effect (typewriter | scramble | comet), read from
// data-fx-effect. Fail-safe: defaults to "typewriter" when the element or
// attribute is absent.
export function fxEffect() {
  return document.getElementById("pito-settings")?.dataset.fxEffect || "typewriter"
}

export function currentTheme() {
  return document.getElementById("pito-settings")?.dataset.theme ||
    document.documentElement.dataset.theme
}

// True when the ctrl+k command palette is open (its overlay is not `hidden`).
// Sidebar / picker keyboard-nav controllers bail while it's open so arrow/Enter
// keys drive ONLY the palette, never both cursors at once.
export function paletteOpen() {
  const el = document.getElementById("pito-command-palette")
  return !!el && !el.classList.contains("hidden")
}
