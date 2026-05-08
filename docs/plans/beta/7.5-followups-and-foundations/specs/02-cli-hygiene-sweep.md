# Phase 7.5 — Step 02 — CLI-side Hygiene Sweep

> Second of two hygiene sweeps for Phase 7.5. Bundles three small, independent
> `pito` CLI cleanups into one cli-impl dispatch and one commit. None of these
> change product behavior intentionally; the ratatui upgrade may have minor
> visual side-effects which are documented and resolved as they surface.

---

## Goal

Land three CLI-side cleanups in a single dispatch:

1. **`cargo fmt --check` drift sweep** — apply rustfmt across `extras/cli/` so
   `cargo fmt --check` is clean. About 63 lines of drift across `app.rs`,
   `commands/tui.rs`, `keys.rs`, `ui/dashboard.rs`, `ui/mod.rs`,
   `ui/operation_progress.rs`, `ui/videos.rs`, `widgets/mod.rs` per the existing
   follow-up.
2. **Dependabot advisory #1** — bump `ratatui` from `0.29.x` to `0.30.x` to
   clear the `lru` (`RUSTSEC-2026-0002`) and `paste` (`RUSTSEC-2024-0436`)
   advisories. Fix any TUI-API breakage that surfaces during the bump.
3. **Screen-layout parity pass** — align every `pito` CLI screen with its Rails
   counterpart per the `follow-ups.md` "screen layout parity" entry. Rails
   dictates the canonical layout; the CLI follows. Sweep all screens, surface
   every discrepancy as a list, fix in the same dispatch (Q4 default).

This spec is intentionally written so that ALL THREE items happen in ONE
dispatch — bundling the rustfmt sweep with the ratatui bump means the
ratatui-bump diff stays readable (no rustfmt-vs-bump confusion in the patch);
bundling the parity pass means a single visual gate covers both the bump's
render side-effects AND the parity changes.

## Files touched

### Item 1 — rustfmt drift sweep

Run `cargo fmt --manifest-path extras/cli/Cargo.toml` over the workspace once.
Files touched (per the existing follow-up entry, may have grown):

- `extras/cli/src/app.rs`
- `extras/cli/src/commands/tui.rs`
- `extras/cli/src/keys.rs`
- `extras/cli/src/ui/dashboard.rs`
- `extras/cli/src/ui/mod.rs`
- `extras/cli/src/ui/operation_progress.rs`
- `extras/cli/src/ui/videos.rs`
- `extras/cli/src/widgets/mod.rs`

Verification: `cargo fmt --check --manifest-path extras/cli/Cargo.toml` returns
zero diff.

### Item 2 — ratatui 0.29 → 0.30 bump

- `extras/cli/Cargo.toml` — bump `ratatui` to `0.30.x` (verify the latest minor
  at the time of the bump). Other crates ride along if the lockfile resolves.
- `extras/cli/Cargo.lock` — refreshed via `cargo update`.

Expected breakage surface (ratatui 0.30 changelog has API churn — the agent
reads the changelog before bumping and addresses each callsite):

- Likely renames around layout / widget / event APIs.
- Possible `Frame` lifetime changes.
- Possible `Block` / `Paragraph` / `Table` / `Tabs` signature changes.

The cli-impl agent fixes breakage as it surfaces and notes each in the session
log. Q3 default = "accept the breakage and let the cli-impl agent solve" — no
screenshots-before/after gate.

Verification:

- `cargo audit` no longer reports `RUSTSEC-2026-0002` or `RUSTSEC-2024-0436`.
- `cargo build --release` clean.
- `cargo test` green.
- `cargo clippy --all-targets --all-features -- -D warnings` clean.

### Item 3 — Screen-layout parity pass

Source of truth: the matching Rails ERB views. Read each ERB, then align the CLI
screen.

Screens to walk (Q4 default = full sweep):

- **Channels list (`/channels`)** ↔ `extras/cli/src/ui/channels.rs`.
- **Channel detail (`/channels/:id`)** ↔ `extras/cli/src/ui/channel_detail.rs`.
- **Videos list (`/videos`)** ↔ `extras/cli/src/ui/videos.rs`.
- **Video detail (`/videos/:id`)** ↔ `extras/cli/src/ui/video_detail.rs`.
- **Dashboard (`/`)** ↔ `extras/cli/src/ui/dashboard.rs`.
- **Search (`/search`)** ↔ `extras/cli/src/ui/search.rs`.
- **Settings (`/settings`)** ↔ whatever CLI screen approximates it (the CLI does
  not currently mirror Settings; if the user's intent is "no settings screen in
  the CLI", document that as the parity resolution rather than building a
  screen).

Known discrepancies pre-flagged in `follow-ups.md`:

1. **Channel detail top action legend.** The CLI shows
   `[view] [sync] [delete]   (v) view  (Y) sync  (D) delete  (s) star` at the
   top. Web shows only `[view] [sync] [delete]` in the breadcrumb actions. The
   `(s) star` keystroke hint should NOT appear at the top — star/unstar lives
   inline on the Starred row.
2. **Sync link placement on channel detail.** Verify the CLI's `[sync]` button
   placement matches web's breadcrumb-actions-row placement.

Other discrepancies the cli-impl agent finds during the sweep get captured in
the dispatch session log under a "discrepancies surfaced" heading, and each is
fixed in the same dispatch.

**Out of scope** (per the follow-up entry):

- Adding NEW features to either side. The keyboard-shortcuts spec
  (`04-keyboard-shortcuts.md`) is its own dispatch; this sweep does NOT add
  Rails-side keyboard shortcuts.
- Refactoring the visual design system itself.
- Adding screens that don't yet exist on one side.

This sweep aligns EXISTING screens. Pure parity, not feature parity.

## Acceptance

- [ ] `cargo fmt --check --manifest-path extras/cli/Cargo.toml` returns zero
      diff.
- [ ] `cargo audit` no longer reports `RUSTSEC-2026-0002` or
      `RUSTSEC-2024-0436`. If either persists, the agent identifies the residual
      path with `cargo tree --invert <crate>` and bumps the closer dependency.
- [ ] `extras/cli/Cargo.toml` pins `ratatui = "0.30.x"`.
- [ ] `cargo build --release --manifest-path extras/cli/Cargo.toml` clean.
- [ ] `cargo test --manifest-path extras/cli/Cargo.toml` green.
- [ ] `cargo clippy --all-targets --all-features -- -D warnings` clean.
- [ ] Channel-detail top action legend matches web's breadcrumb-actions layout
      (no `(s) star` hint at the top).
- [ ] Sync-link placement on channel detail matches web.
- [ ] All screens listed in Item 3 walked; the dispatch session log lists every
      discrepancy surfaced during the walk and notes how each was resolved.
- [ ] GitHub Dependabot alert #1 clears after the commit pushes.

## Manual test recipe

1. From the repo root, `cd extras/cli && cargo fmt --check` — clean.
2. `cargo audit` — no advisories on `lru` or `paste` related to ratatui's tree.
3. `cargo build --release` — successful build.
4. `cd ../..; bin/dev` (web Puma + Sidekiq + Tailwind start). In a second
   terminal, run the freshly-built `pito` binary
   (`extras/cli/target/release/pito`) against the local server.
5. Walk every screen the parity pass touched:
   - Channels list: column layout, filter chips, sort indicators match
     `/channels` in the browser.
   - Channel detail: top action legend matches `[view] [sync] [delete]` only —
     no extra `(s) star` hint. Sync-link placement matches web's.
   - Videos list, video detail, dashboard, search: each lines up with its Rails
     counterpart.
6. Visit each Rails surface in the browser side-by-side with the CLI. Confirm
   the visual / link-placement parity.
7. After commit pushes, watch the GitHub Dependabot alert — it should clear
   within minutes of the push.

## Cross-stack scope

- `pito` CLI (`extras/cli/`) — **in scope.**
- Rails — **out of scope** (the parity sweep reads ERB views as a
  source-of-truth reference; the spec does not modify them).
- MCP — **out of scope.**
- Cloudflare Pages website — **out of scope.**

## Open questions

- **Q3** (from `00-phase-overview.md`) — ratatui 0.30 upgrade tolerance. Default
  = accept TUI-render side-effects, fix breakage as it surfaces.
- **Q4** (from `00-phase-overview.md`) — screen-layout parity scope. Default =
  full sweep.

## Follow-ups created

- **Future ratatui bumps.** When the next ratatui breaking release ships, the
  same shape applies: bump, fix breakage, re-run `cargo audit`. Park as a
  follow-up under "next time the CLI is touched substantively".

## Decisions (locked)

- **One commit.** All three items ship together. Visual regressions from the
  ratatui bump are caught by the parity pass's manual walk.
- **Source of truth is Rails.** The CLI follows web. Where the CLI diverges
  intentionally (terminal-only keystroke hints in the help screen), the dispatch
  session log documents the divergence and keeps it.
- **No keymap changes in this dispatch.** Keyboard schema is the domain of
  `04-keyboard-shortcuts.md` (which mirrors the CLI's schema into Rails). The
  parity sweep here is layout-only.
