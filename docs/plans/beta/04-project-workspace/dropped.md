## 2026-05-11 — `[bulk]` toggle retired; checkboxes always visible

**What:** Drop the `[bulk]` mode-toggle UI across web and TUI. Checkboxes are
now always visible on every list surface; the `b` keybinding that entered /
exited bulk mode is gone; the `[bulk]` and `[cancel]` toggle links are gone. The
bulk-as-foundation URL pattern (`/<action>s/:type/:ids`) survives — only the
toggle UI was retired.

**Why:** Friction with no benefit — selecting rows shouldn't require a
mode-switch.

**Where:** Commits `f2e086e` (projects bulk: checkboxes always visible, drop
`[bulk]` toggle), `bf977c8` (TUI: drop bulk-mode gate; selection always on),
`1651b4f` (TUI toolbar: drop decorative `[bulk]` span on channels and videos),
`8f29b75` (Rails keymap / help-modal cleanup: drop `b` bulk-toggle + space
bulk-mode gates) — all 2026-05-11.
