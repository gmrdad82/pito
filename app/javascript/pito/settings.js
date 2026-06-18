// Reads sound/fx settings from the server-rendered element.
// The element is replaced via Turbo Stream when settings change.
// Fail-open: when the element or attribute is absent, treat sound/fx as enabled (true).

export function soundEnabled() {
  return document.getElementById("pito-settings")?.dataset.sound !== "false"
}

export function fxEnabled() {
  return document.getElementById("pito-settings")?.dataset.fx !== "false"
}

export function currentTheme() {
  return document.getElementById("pito-settings")?.dataset.theme ||
    document.documentElement.dataset.theme
}
