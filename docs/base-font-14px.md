# Base font 16px → 14px (test)

> Status: draft

## Sign-off

- [x] Drafted — 2026-06-12
- [ ] Audited — _pending_

## North star

Drop the app-wide base font size from 16px to 14px so the whole monospace UI
renders one notch tighter. A test change on the current branch.

## Locked decisions

| Topic          | Decision                                                                                                                                                                                                                                                        |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Source of size | The `--text-base` token in the `@theme` block of `app/assets/tailwind/application.css`.                                                                                                                                                                         |
| Real cause     | The token alone is currently a **no-op** for the rendered base: nothing sets a root font-size, so the tree inherits the browser default (16px) through the `* { font-size: inherit }` base rule. The token only feeds the (largely unused) `text-base` utility. |
| Fix            | Two parts — (1) set the token to 14px; (2) anchor `html { font-size: var(--text-base); }` (element selector outranks `*`, so it becomes the single source of truth the whole tree inherits).                                                                    |
| Exceptions     | Leave the wordmark-logo `font-size: 18px` exception and the comment wording untouched.                                                                                                                                                                          |
| Scope          | CSS only. No component, ERB, or spec changes — there are no specs asserting a px base.                                                                                                                                                                          |

## Phase index

- P0 — Lower the base font to 14px

## P0 — Lower the base font to 14px

- [x] T0.1 Change `--text-base` from `16px` to `14px` in the `@theme` block of `app/assets/tailwind/application.css`. complexity: [low]
- [x] T0.2 Add `font-size: var(--text-base);` to the `html { … }` rule in `app/assets/tailwind/application.css` so the token actually drives the rendered base. complexity: [low]
- [ ] T0.3 Smoke-check: load the app and confirm the UI renders at 14px (computed `font-size` on `html` = 14px). complexity: [manual]
- [ ] T0.4 Commit: `Lower base font from 16px to 14px`. complexity: [manual]
