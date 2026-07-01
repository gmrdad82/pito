// Reads sound + theme settings from the server-rendered element.
// The element is replaced via Turbo Stream when settings change.
// Fail-open: when the element or attribute is absent, treat sound as enabled (true).
//
// (Item 18 removed the fx/motion settings — content text-reveal is gone and the
// widget reveals always play, so there is no fx toggle / reveal-effect to read.)

export function soundEnabled() {
  return document.getElementById("pito-settings")?.dataset.sound !== "false"
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
