# Phase 4 — Terminal App `pito-sh`

> **Goal:** Build a terminal client for Pito in Rust + Ratatui. Visually
> inspired by `btop`, `gitui`, and `bottom`. Operates against Pito's JSON API on
> Web Puma using bearer-token auth from Phase 3. **This phase is also where the
> design system converges across all clients** — web, MCP, terminal — because
> the terminal is the most constraining surface and forces decisions that web
> alone wouldn't.

**Repo:** `~/Dev/pito-sh` (created in Phase 1).

**Depends on:** Phase 3 (token-based JSON auth + scope catalog).

**Unblocks:** Phase 5 (Slack probe shares token/scope patterns and design
language). Locks the design system before Phase 11's video workflow features add
many new screens.

---

## Why Phase 4 is now

The terminal app sits here, before YouTube API integration, for four reasons:

1. **Design forcing function.** The user is design-sensitive about Pito's
   bracketed-link, monospace, retro aesthetic. Implementing it in a terminal
   forces decisions about color palette, spacing, focus indicators, keybindings,
   and chart rendering that should be locked **before** Phase 11 builds dozens
   of new screens. Building those screens against a stable design vocabulary is
   dramatically cheaper than refactoring them later.
2. **API surface validation.** With `yt:*` scopes in place from Phase 3, the
   terminal app has everything it needs to authenticate. Building it exclusively
   against fake seed data validates the JSON API surface for headless clients.
   If the API is awkward for a terminal client, it's awkward for Slack (Phase
   5), for any future automation, and for MCP. Better to find that out now.
3. **Cross-client keyboard taxonomy.** Web and terminal share a shortcut
   language from day one, documented in `pito/docs/design.md`. Phase 11 inherits
   the taxonomy; new screens just consume the existing keybindings.
4. **It's a fun probe-style sub-project.** A pure Rust + Ratatui project is
   small enough to scope but distinct enough to validate that Pito's API is
   genuinely client-agnostic. If `pito-sh` ends up something the user actually
   uses daily, great. If it ends up a "design alignment exercise that taught us
   things," also great — and the lessons survive in the API and design system
   regardless.

The terminal app talks to **Web Puma's JSON API** at `app.pitomd.com`. It does
not use MCP. (MCP is for AI clients; the terminal app is a programmatic client.
They share the auth model — `ApiToken` with scopes — but use different
endpoints.)

---

## In scope

### Stack

- **Rust** (latest stable). Project name: `pito-sh`.
- **Ratatui** for TUI rendering.
- **Crossterm** for terminal handling.
- **Reqwest** for HTTP.
- **Tokio** for async runtime.
- **Serde** + **serde_json** for JSON.
- **`directories`** crate for config paths.
- **`keyring`** crate for token storage in OS keyring (with file fallback).
- **`oauth2`** crate for the auth flow (PKCE-based authorization code).
- **`anyhow`** + **`thiserror`** for error handling.

### Auth flow

The terminal app authenticates by acting as an OAuth-style client against Pito.
**In this phase**, the auth flow is a minimal authorization-code flow with PKCE
that mints an `ApiToken` directly in Pito's database. **In Phase 12**, when
Doorkeeper is introduced, this flow gets replaced by standard OAuth 2.0
endpoints and the app uses standard refresh tokens.

The Phase 4 flow:

1. On first launch, `pito-sh` opens the user's browser to
   `https://app.pitomd.com/auth/cli/start?code_challenge=...&port=<localhost-port>`
2. The user is already logged into the web app (single-user, seeded user
   implicitly current). The page asks them to confirm: "Authorize `pito-sh` with
   scopes `yt:read yt:write`?"
3. On confirmation, Pito mints an `ApiToken` for the seeded user with the
   requested scopes and redirects to
   `http://localhost:<port>/callback?code=<code>`
4. `pito-sh` is listening on that port; receives the code; exchanges it via
   `POST /auth/cli/exchange` (with PKCE verifier) for the token plaintext
5. Token stored in OS keyring (preferred) or `~/.config/pito-sh/tokens.json`
   chmod 600 (fallback)
6. Subsequent launches read the token; if revoked or invalid, re-run the flow

The default scope set requested by `pito-sh` is `yt:read yt:write`. The user can
opt into `yt:destructive` by re-running the auth flow with a flag
(`pito-sh login --destructive`) — separate code path that requests the elevated
scope.

### Screens (matching the web app)

The terminal app mirrors every web screen as closely as TUI constraints allow:

- **Dashboard** — 4 ASCII/Unicode charts with the same time-range selectors (7d
  / 30d / 90d / 1y / all)
- **Channels picker** — sortable table, multi-select via `Space`, bulk actions
  via single-letter shortcuts
- **Channel show** — multi-pane workspace, up to 5 panes side-by-side
  (responsive collapse to vertical stack on narrow terminals, mirroring the
  web's mobile behavior)
- **Videos picker / show** — same structure as channels
- **Saved Views** — list, restore, delete
- **Search** — overlay triggered by `/`, live results from Web Puma's search
  endpoint
- **Settings** — read-only display in this phase (max_panes, theme, search
  status). Token management lives in the web Settings UI; the terminal doesn't
  need its own.

### Charts in TUI

Ratatui's `Chart` widget is functional but basic. For the dashboard's four
charts, use Ratatui's built-in chart for v1; revisit with a richer renderer
(e.g., a custom braille-pattern renderer) only if v1 looks inadequate. No
animation. Document the choice in `challenges.md`.

### Action screens

The terminal mirrors the web's dry-run-then-confirm flow for destructive
operations:

- Bulk delete: select rows, press `d`, see dry-run preview from
  `GET /deletions/new.json`, press `Enter` to confirm, see Sidekiq progress
  polled via `GET /bulk_operations/:id.json`
- Single delete / edit / create: same shape as web

The terminal app **never duplicates business logic**. Every action calls a Web
Puma JSON endpoint that already exists for the web UI. If an endpoint doesn't
have a JSON responder, this phase adds one (it's a
`respond_to do |format| format.json` addition; no logic is reimplemented).

### Theme

Match Pito's web theme tokens (defined in `pito/docs/design.md`). Light theme
uses terminal defaults; dark theme uses the Dracula-inspired palette already
documented. Pull theme tokens from `design.md` and translate to ANSI/RGB color
codes. Keep one source of truth — the design.md tokens.

### Keyboard shortcut taxonomy

This phase establishes the cross-client keyboard taxonomy. Document in
`pito/docs/design.md` under a new "Keyboard Shortcuts" section. Web and terminal
share the same letters where possible:

```
?              — help overlay
/              — focus search
g d            — go to dashboard
g c            — go to channels
g v            — go to videos
g s            — go to saved views
g e            — go to settings (e for "settings" because s is taken by saved views)
j / k          — down / up
h / l          — left / right (or pane navigation)
Space          — multi-select toggle in pickers
Enter          — open / drill in
q              — close pane / back
Esc            — cancel / close overlay
n              — toggle dark mode
d              — initiate delete (with confirm)
e              — edit focused row
c              — create new (from picker context)
:q             — quit
Ctrl+C         — quit
```

Web app shortcuts are audited against this taxonomy. Any web shortcut that
conflicts (e.g., the existing dark-mode toggle, search focus) is realigned in
this phase. The terminal and web mirror each other.

### API surface verification

Audit Pito's controllers: every screen the terminal renders needs a JSON
endpoint returning the data it needs. Existing controllers from Alpha typically
respond only to HTML; this phase adds JSON responders to those that the terminal
consumes. Document the JSON API endpoints used by `pito-sh` in a new
`pito/docs/api.md` (not exhaustive — only the endpoints `pito-sh` uses, plus
their request/response shapes).

The terminal app respects `yt:read` for read endpoints and `yt:write` for
mutations. Destructive operations (bulk delete, single delete) require
`yt:destructive`; the terminal raises a clear "this token lacks `yt:destructive`
— re-authorize with --destructive" if the user attempts a destructive action
with a non-destructive token.

### Out of scope

- Video upload from terminal (Phase 11; technically infeasible for resumable
  uploads from TUI without browser handoff)
- Interactive crosshair on charts (Ratatui crosshair-on-hover is hard; static
  charts are fine)
- Terminal-specific MCP integration (the terminal app is an HTTP/JSON client; it
  does not act as an MCP client)
- Distribution / packaging (Theta concern; for Beta, `cargo build --release` and
  the user runs the binary)
- Multi-platform support beyond Linux (the user runs Omarchy/Linux;
  macOS/Windows are bonus, not required)
- Doorkeeper-based OAuth (Phase 12 — until then, the ad-hoc `/auth/cli/*` flow
  is acceptable)

---

## Plan checklist

### Repo setup

- [ ] Confirm `pito-sh` scaffolding from Phase 1 (README, CLAUDE, LICENSE)
- [ ] `cargo init` in `~/Dev/pito-sh`
- [ ] Add dependencies to `Cargo.toml`: ratatui, crossterm, tokio (with
      `rt-multi-thread`), reqwest, serde, serde_json, directories, keyring,
      oauth2, anyhow, thiserror
- [ ] Module structure: `src/app/` (state), `src/ui/` (Ratatui widgets),
      `src/api/` (HTTP client), `src/auth/` (OAuth + keyring), `src/theme/`
      (color tokens), `src/keys/` (keybinding handlers)
- [ ] Initial commit: minimal hello-world that opens a terminal and quits
      cleanly

### Pito side: CLI auth endpoints

- [ ] `POST /auth/cli/start` — accepts `code_challenge` and `redirect_port`;
      creates a short-lived authorization code; returns the consent URL the
      browser should hit
- [ ] `GET /auth/cli/authorize` — the browser hits this; if the seeded user is
      implicitly current, shows a consent screen ("Authorize `pito-sh` with
      scopes `yt:read yt:write`?"); on confirmation, redirects to
      `http://localhost:<port>/callback?code=<code>`
- [ ] `POST /auth/cli/exchange` — accepts `code` + `code_verifier`; validates
      PKCE; mints an `ApiToken` with the requested scopes; returns plaintext
      token
- [ ] Codes are single-use and expire in 60 seconds
- [ ] PKCE verifier required (S256 challenge method)
- [ ] Specs cover: full happy path, code expiry, code reuse rejection, PKCE
      failure, redirect-port validation

### Terminal side: auth flow

- [ ] Spin up a one-shot HTTP server on a random localhost port (port range, not
      fixed; pass to Pito as `redirect_port`)
- [ ] Generate PKCE verifier + challenge
- [ ] Open browser via `xdg-open` (Linux); fallback to printing the URL
- [ ] Receive callback, exchange code, store token
- [ ] Token storage: try OS keyring first; on failure (no keyring service),
      fallback to `~/.config/pito-sh/tokens.json` chmod 600
- [ ] Refresh / re-auth flow: if a request returns 401, prompt user to re-run
      the auth flow

### Core screens

- [ ] Dashboard with 4 ASCII charts and time-range selectors
- [ ] Channels picker (sortable table, multi-select, bulk actions)
- [ ] Channel show with multi-pane workspace (max 5 panes; responsive collapse)
- [ ] Videos picker / show / multi-pane
- [ ] Saved Views screen
- [ ] Search overlay (`/` to open, live results)
- [ ] Settings screen (read-only display)

### Action screens

- [ ] Bulk delete: select → `d` → preview → confirm → progress
- [ ] Single delete: `d` on focused row → preview → confirm
- [ ] Channel/video edit: `e` → in-line form → save (calls
      `PATCH /api/channels/:id.json`)
- [ ] Channel/video create: `c` from picker → in-line form → save (calls
      `POST /api/channels.json`)

### Theme + design alignment

- [ ] Read `pito/docs/design.md` to extract color tokens for light + dark themes
- [ ] Implement a `theme` module that maps the tokens to ANSI/RGB
- [ ] Bracket convention: render `[label]` for actionable items consistently
- [ ] Add a "Keyboard Shortcuts" section to `pito/docs/design.md` listing the
      cross-client taxonomy
- [ ] Audit web app keybindings; realign any that conflict with the new taxonomy
- [ ] Add `?` help overlay in both web and terminal showing the shortcuts

### API surface verification

- [ ] Audit Pito controllers; identify endpoints the terminal needs
- [ ] Add JSON responders to controllers missing them
      (`respond_to do |format| format.json`)
- [ ] Endpoints follow the existing scope-enforcement pattern from Phase 3
      (`require_scope!`)
- [ ] Document the JSON API surface in a new `pito/docs/api.md` (focus:
      endpoints `pito-sh` uses, plus request/response shapes)

### Documentation

- [ ] `pito-sh/README.md`: install, build, first-run auth flow, troubleshooting
- [ ] `pito-sh/CLAUDE.md`: context for Claude Code working in this repo
- [ ] `pito/docs/design.md`: keyboard shortcuts section, terminal-specific
      design notes (palette translation, bracket conventions, multi-pane
      responsive behavior)
- [ ] `pito/docs/api.md`: JSON API endpoints used by terminal client
- [ ] `pito/docs/architecture.md`: terminal app added to client diagram

### Validation

- [ ] `cargo test` — Rust tests pass
- [ ] `cargo clippy -- -D warnings` — no warnings
- [ ] `cargo fmt --check` — formatted
- [ ] Pito Rails specs: all green (new JSON endpoints have specs)
- [ ] Manual: launch `pito-sh`, complete auth flow, navigate all screens,
      perform CRUD on a channel, run bulk delete with progress
- [ ] Manual: confirm shortcuts work identically in web and terminal where they
      overlap
- [ ] Manual: dark mode toggle (`n`) flips terminal theme
- [ ] Manual: a destructive operation with a non-destructive token shows the
      clear "re-authorize with --destructive" message
- [ ] Brakeman (Pito side), bundler-audit (Pito side), `cargo audit` (terminal
      side) — clean
- [ ] Dependabot reviewed after `pito-sh` deps added

---

## Specs requirements

### Pito side

- Request specs for new JSON endpoints (`/api/channels`, `/api/videos`,
  `/api/dashboard`, `/api/search`, `/auth/cli/*`). Auth and scope coverage on
  each.
- Specs for the auth code flow: start, authorize, exchange. Code expiry, reuse
  rejection, single-use enforcement, PKCE validation.
- Specs for the consent screen rendering and confirmation flow.

### Terminal side

- Unit tests for theme parsing, keybind dispatch, the API client (with mocked
  HTTP via `wiremock` or similar), state transitions in screens.
- Integration tests for the auth flow (spinning up a mock HTTP server,
  simulating browser callback).
- TUI rendering tests are minimal — Ratatui is hard to integration-test; rely on
  manual verification for screen layouts.

### Cross-client

- A manual checklist of shortcuts in `pito/docs/design.md` that the user runs
  through in both web and terminal during phase validation.

## Security requirements

- Token storage: OS keyring preferred. File fallback is `chmod 600`, parent
  directory `chmod 700`.
- HTTPS only for `/auth/cli/*` endpoints. Localhost callback is HTTP (standard
  OAuth pattern; PKCE protects).
- PKCE on the auth code flow (S256). Code single-use, 60-second expiry.
- Bearer token in `Authorization` header, never in query params.
- The Pito CLI auth endpoints are tenant-scoped — they mint tokens for the
  seeded user only. Multi-tenant CLI auth is a Theta concern.
- Brakeman (Pito side): no new warnings.
- bundler-audit (Pito side): clean.
- `cargo audit` (terminal side): clean.
- Dependabot: enabled on `pito-sh` repo.
- `pito/docs/design.md`: terminal palette and keyboard shortcuts documented.

## Manual testing checklist

The user runs through this before commit:

1. Build: `cd ~/Dev/pito-sh && cargo build --release`
2. Run: `./target/release/pito-sh` — first launch detects no token, opens
   browser
3. Browser shows consent screen for `yt:read yt:write`; click confirm
4. Browser redirects to localhost callback; terminal stores the token
5. Terminal renders the dashboard with seeded data
6. `g c` → channels list. `j/k` to navigate. `Space` to multi-select.
7. `d` on selected channels → dry-run preview from Web Puma → `Enter` to confirm
   → Sidekiq progress polled
8. `/` → search overlay; type a query → live results
9. `n` → toggle dark theme; verify colors flip
10. `g v` → videos. `Enter` on a row → multi-pane workspace.
11. `q` → close pane. `q` again → back to picker.
12. `g s` → saved views. Restore one.
13. `?` → help overlay shows all shortcuts
14. Open `app.pitomd.com` in a browser; confirm the same shortcuts work there
15. Try a destructive action with the non-destructive token — clear error
    message
16. `pito-sh login --destructive` → re-auth flow with elevated scope; retry
    destructive — succeeds
17. `:q` or Ctrl+C — clean exit

---

## Challenges to anticipate

- **Charts in TUI.** Ratatui's `Chart` widget is basic. v1 uses it as-is;
  document the limitation in `challenges.md`. If it looks inadequate, the user
  makes the call on whether to invest in a custom braille-pattern chart renderer
  (interesting, time-consuming) or accept the limitation (boring, fast).
- **Multi-pane responsive layout.** Five panes side-by-side may be too narrow on
  standard terminals. Implement responsive collapse to vertical stacking under a
  width threshold, mirroring the web's mobile behavior. Document the threshold.
- **Browser launch on Wayland (Omarchy).** `xdg-open` should work; fallback is
  to print the URL for the user to paste. Test both paths.
- **Token refresh.** Phase 4 doesn't refresh; tokens are long-lived. Phase 12
  introduces Doorkeeper with proper refresh tokens; the terminal app gets
  refactored to use refresh flow at that point.
- **Cross-client shortcut conflicts.** Some web shortcuts may conflict with
  terminal-native bindings (`Ctrl+W` is "close window" in both web and many
  terminals). Document conflicts in `challenges.md` and pick consistent winners
  — when in doubt, go with the terminal-native binding because the web has more
  flexibility to remap.
- **Keyring service availability.** Some Linux environments don't have a keyring
  service running. The file fallback covers this; document the failure mode
  clearly so the user knows when they're using fallback storage.
- **Web Puma JSON endpoint coverage.** Auditing every controller and adding JSON
  responders is mechanical but tedious. Some controllers may have HTML-only
  logic (e.g., flash messages, redirects) that doesn't translate to JSON.
  Document the patterns; build a small response helper that wraps the common
  cases.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. Rust toolchain is available on the user's machine (`rustup --version`).
2. The auth flow mints tokens with default scopes `yt:read yt:write` (no
   `yt:destructive` by default). User opts into `yt:destructive` via
   `pito-sh login --destructive`.
3. The keyboard shortcut taxonomy in this plan is acceptable. If the user wants
   different letters, capture revisions before building — realigning later costs
   more.
4. Browser auto-launch is acceptable. Some users prefer URL-print only; make
   this configurable via `pito-sh login --no-browser`.
5. Charts use Ratatui's built-in chart widget for v1. Custom renderer is a
   follow-up if v1 falls short.
6. The terminal app is Linux-only for Beta. macOS/Windows support is a Theta
   concern (or never).
