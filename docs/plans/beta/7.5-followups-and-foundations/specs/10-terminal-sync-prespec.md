# Phase 7.5 — Step 10 — Terminal Sync (pre-spec)

> **PRE-SPEC.** Symmetric to spec 09 (`mcp-sync-prespec`) but for the `pito` CLI
> / TUI. Captures the plausible interpretations of "terminal sync", surfaces
> open questions, parks the work until the user resolves the meaning. No code
> dispatches off this doc as-is.

---

## What we have (rooted in code)

The `pito` CLI is a TUI client of the Rails API:

- Default invocation (`pito`) launches the TUI. Subcommands (`pito footage`,
  `pito help`, `pito version`, future ones) extend the surface.
- TUI reads the API on demand (`get_dashboard`, `get_channels`, `get_videos`,
  `get_channel_detail`, `get_video_detail`).
- Bulk operations (delete, sync) use the `/syncs/...` and `/deletions/...` URL
  surfaces; the TUI confirms in an overlay and POSTs.
- Post-confirm "polling window" — `extras/cli/src/app.rs`'s `tick` loop
  refetches state for a few seconds after a sync confirm fires, animating the
  affected rows. After the window expires, manual refresh (`r` or screen
  navigation) is the only path to see new state.
- No real-time push from Rails to the CLI. No subscription / websocket / SSE.

The footage importer (`pito footage import`) is a one-shot subcommand — it diffs
local vs remote, confirms in the TUI, posts changes, and exits. Not a long-lived
sync surface.

## Plausible interpretations of "terminal sync"

### Interpretation A — Live state mirroring between CLI and web

The user has the TUI open in one terminal AND the web app open in the browser.
They want: a star toggle on the web UI to reflect in the CLI immediately (and
vice versa), without manual refresh in the CLI.

What "terminal sync" would mean here:

- The CLI subscribes to a Rails-side push stream (Server-Sent Events from the
  JSON API, or websockets via the existing ActionCable surface).
- On state-change events (channel star, channel connected, video star, sync
  started/finished), the CLI invalidates the affected row's local cache and
  refetches.
- Counterpart on the web side already exists (Turbo Streams).

Probable cost: medium-high. New transport surface (SSE or websocket-equivalent
over JSON), state-change broadcast wiring on the Rails side, refetch logic on
the CLI side. The polling window pattern that exists post-confirm could
generalize, but the on-demand refetch is fundamentally different from a push
model.

### Interpretation B — `pito sync` subcommand

A new subcommand mirroring `pito footage`'s shape, but for a different domain.
E.g. `pito sync notes` reads markdown files from a local directory and
reconciles them with the project's notes; `pito sync timeline` reads a Resolve /
Premiere export and reconciles with the Timeline rows.

Probable cost: medium. Mirrors the existing `pito footage import` plumbing.

### Interpretation C — Bidirectional notes sync

A specific case of B, but worth calling out. The Mobile-via-MCP `save_note` flow
drops markdown into `docs/notes/`. The Desktop user curates and commits. A
terminal-side `pito sync notes` could help the Desktop user triage by listing
un-curated notes, opening them in `$EDITOR`, deleting outdated ones, etc. —
without leaving the terminal.

This overlaps with spec 09's Interpretation B; if the user picks B for both, the
two specs collapse into one with a Rails surface and a CLI surface.

### Interpretation D — Something else

Captured as a sub-question.

## Open questions

**Q13.a — Which interpretation is the user's "terminal sync"?**

- (A) Live state mirroring (push from Rails to CLI).
- (B) `pito sync <thing>` subcommand mirroring `pito footage`.
- (C) Bidirectional notes sync (overlaps spec 09's B).
- (D) Other — describe.

**Q13.b — Relationship to spec 09 ("MCP sync").** Are these the same concept
under two labels, or two different concepts? The master agent suspects there's
overlap (esp. C above ↔ spec 09's B), but doesn't want to merge without the
user's confirmation.

**Q13.c — Phase ordering.** A and B are independent of Phase 8. If A's
"state-change events" includes "sync finished", that depends on Phase 8 having
real sync to finish. So A's full value requires Phase 8 first.

## Master agent's lean

**No lean** — same as spec 09. The phrase needs the user's disambiguation.

If the master had to guess: **B** is the most likely interpretation given the
user's existing pattern (`pito footage import` is mature and well-loved; "what's
the next subcommand that fits this shape" is a natural product question). But
that's a guess, not a lean.

## What happens next

After the user answers Q13.a–c (and resolves the overlap with spec 09):

- (A) — `10b-cli-state-push.md` becomes a real spec, paired with a Rails-side
  spec for the broadcast surface.
- (B) — `10b-pito-sync-<domain>.md` becomes a real spec, where `<domain>` is
  whichever surface the user picked (notes, timelines, etc.).
- (C) — merges with spec 09's B; one combined spec.
- (D) — depends.

## Files touched

None in this pre-spec.

## Acceptance

- [ ] User answers Q13.a, Q13.b, Q13.c.
- [ ] Master decides: real spec, defer, or merge with spec 09.
- [ ] Follow-up architect dispatch (if applicable) produces the implementation
      spec; this file closes with a pointer.

## Manual test recipe

Not applicable.

## Cross-stack scope

Decided once Q13.a–c are answered. Likely:

- (A) — Rails + CLI both in scope.
- (B) — CLI in scope; Rails in scope only if a new API endpoint is needed.
- (C) — Rails + CLI both in scope; merges with spec 09.

## Follow-ups created

None until answered.

## Decisions (locked)

- **No spec implementation off this doc.** Pre-spec only.
- **The CLI's existing post-confirm polling window stays as-is.** Whichever
  direction "terminal sync" takes, the polling window's narrow purpose (animate
  the affected rows for a few seconds after a confirm) is unchanged.
- **No reverting `pito footage import` to a long-lived process.** The footage
  importer's one-shot shape is a feature, not a limitation.
