// Reads sound/fx/expand-all settings from the server-rendered element.
// The element is replaced via Turbo Stream when settings change.
// Fail-open: when the element or attribute is absent, treat sound/fx as enabled (true).
// Fail-closed: when the element or attribute is absent, treat expand-all as disabled (false).

export function soundEnabled() {
  return document.getElementById("pito-settings")?.dataset.sound !== "false"
}

export function fxEnabled() {
  return document.getElementById("pito-settings")?.dataset.fx !== "false"
}

export function expandAllEnabled() {
  return document.getElementById("pito-settings")?.dataset.expandAll === "true"
}
