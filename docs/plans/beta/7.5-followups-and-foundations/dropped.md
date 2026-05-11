# Phase 7.5 — Follow-ups Sweep + Concept Foundations · Dropped

> Items removed (or recommended for removal) from this phase's scope by the
> 2026-05-09 realignment. See `docs/realignment-2026-05-09.md` for the top-level
> direction map.

## 2026-05-09 — Pre-spec recommendations

The user's direction conversation locked recommendations on the three Phase 7.5
pre-specs that were "specced but not clarified." Architect's recommendations
below; user confirms or overrides before any close-out docs-keeper dispatch.

### 09 — MCP sync (recommend drop in current form)

`specs/09-mcp-sync-prespec.md` parked four interpretations of "MCP sync." The
realignment supersedes the abstract framing: the Mobile notes (notably
`2026-05-09-19-14-10-calendar-and-notifications.md`) specify concrete MCP tool
surfaces per domain (`calendar_*`, `purchase_*`, `notifications_*`,
`milestone_rule_*`). The right work unit is "MCP tool catalog expansion" landing
alongside each domain's Rails spec — see realignment doc work unit 9.

**Recommend:** close the pre-spec with a one-line pointer to
`docs/realignment-2026-05-09.md` work unit 9. If the user actually meant
Interpretation A (state-mirroring web↔MCP via Turbo Streams), file as a
follow-up under `docs/orchestration/follow-ups.md` and pick up after the new
domain surfaces stabilize.

### 10 — Terminal sync (recommend drop in current form)

`specs/10-terminal-sync-prespec.md` parked four interpretations of "terminal
sync." The single-install single-database shape locked by ADR 0003 makes
Interpretation A's value (live state-mirroring CLI ↔ web) lower than it seemed:
shared Postgres + the existing post-confirm polling window covers most of the
perceived live-state value. A push channel is substantial new infrastructure for
marginal benefit. Interpretation B (`pito sync <thing>` subcommand) fits cleanly
into the per-domain CLI parity work unit (work unit 10).

**Recommend:** close the pre-spec with a one-line pointer to
`docs/realignment-2026-05-09.md` work unit 10. If the user wanted live
state-mirroring, file as a follow-up.

### 08 — Timelines resurrection (recommend defer)

`specs/08-timelines-resurrection-prespec.md` parked the resurrect / defer call.
Architect's recommendation: defer to a post-YouTube- management work unit (after
the realignment doc's work units 3 + 4 land). The Timeline lifecycle's headline
value (linkage from a rendered NLE export to a published YouTube video) needs
the Video metadata expansion to be useful. Once the Video edit surface ships,
Timeline-export-driven import (a `pito timeline import` subcommand mirroring the
footage importer) becomes the natural next surface.

**Recommend:** keep the pre-spec open, add a "depends on YouTube management
surface landing first" note. No code dispatched off it until then.

## 2026-05-09 — Hygiene items already closed

The following Phase 7.5 hygiene items shipped in flow and are not affected by
the realignment:

- Track A specs 01 (Rails hygiene sweep) — shipped.
- Track B spec 02 (CLI hygiene sweep) — shipped.
- Track C spec 03 (decorator slim resolution) — closed as no-op.
- Track C spec 04 (keyboard shortcuts) — shipped.
- Track C spec 05 (`pito-assets` Docker volume) — shipped.
- Track C spec 06 (footage thumbnails) — partially shipped; the importer-side
  ffmpeg extraction remains open per the plan.

## 2026-05-10 — Pre-specs 08 / 09 / 10 deleted outright

Follow-up cleanup pass to the realignment paperwork sweep. The user confirmed
the 2026-05-09 recommendations above and chose not to preserve the original
pre-spec content. The three files were deleted outright; the durable record
lives in `docs/realignment-2026-05-09.md` and
`docs/orchestration/follow-ups.md`.

- **Pre-spec 08 — Timelines resurrection — deleted.**
  - **Rationale:** Project ↔ Video association is implemented as a direct
    nullable `Video.project_id` and is scheduled in the tenant-drop-and-rebuild
    work (work unit 4 in the realignment doc). The abstract "Timelines
    resurrection" framing is superseded.
  - **Cross-reference:** `docs/realignment-2026-05-09.md` (work unit 4).
- **Pre-spec 09 — MCP sync — deleted.**
  - **Rationale:** superseded by the per-domain MCP coverage matrix. Each domain
    spec going forward declares its own MCP coverage inline; there is no longer
    a standalone "MCP sync" surface to spec.
  - **Cross-reference:** `docs/realignment-2026-05-09.md` (work unit 9 + the
    per-domain coverage matrix posture).
- **Pre-spec 10 — Terminal sync — deleted.**
  - **Rationale:** superseded by the per-domain CLI coverage matrix; same
    posture as 09. Web is the canonical surface; the Rust CLI is best-effort
    parity declared per domain spec.
  - **Cross-reference:** `docs/realignment-2026-05-09.md` (resolved ambiguities
    #3 + work unit 10).

## 2026-05-10 — Final reconciliation

The three pre-spec drops (08 / 09 / 10) are pinned. No additional drops landed
between the 2026-05-10 deletion pass and the Phase 19 close-out. The Cassette-
recording session, YouTube data sync engine, real `top videos` chart rebuild,
URL-hash → query-param sort migration, filter chip group component, and
Meilisearch indexing per-target flag parity remain **deferred** (not dropped) —
they are tracked as carry-forwards in `docs/orchestration/follow-ups.md` per the
close-out's follow-ups disposition table.

- **Item:** no further drops; pre-specs 08 / 09 / 10 disposition confirmed.
- **Rationale:** every other "Deferred workstream" listed in `plan.md` has a
  current trigger condition and stays in the follow-ups backlog rather than
  being dropped from the phase plan.
- **Plan link:** `plan.md > Deferred workstreams` — items remain unchecked
  intentionally; they are queued, not abandoned.
- **Driver:** Phase 19 close-out spec
  (`docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`).

## 2026-05-11 — Step 11 scope drops landed during sub-spec resolution

### `watermark_position` column dropped

**What:** The original Step 11 channel-schema spec proposed a
`watermark_position` enum with four corner values. Dropped entirely; the schema
keeps only the watermark image fields.

**Why:** Q3 resolution + image evidence captured under D21 — YouTube only
supports a right-corner watermark in practice. A four-corner enum encodes
flexibility the upstream API never exposes; the column would be a permanent
liar.

**Where:** commit `5f19aa3` (Phase 7.5 Step 11 + 11a: all 12 questions resolved
(D19-D23 added); 11a foundation spec drafted); decision D21.

### "Select channels to add" multi-select picker form on `/settings/youtube`

**What:** The original Step 11 plan for `/settings/youtube` included a
multi-select picker form where the user would tick which OAuth-discovered
channels to attach. Dropped; channels now auto-add on the OAuth callback with a
duplicate-skip flash.

**Why:** User directive during the Settings/youtube revamp — the picker step is
friction without value (the user just connected the brand account; they want the
channels in). Duplicate-skip handles the only edge that mattered.

**Where:** commit `5253907` — Settings/youtube: channels table per connection,
bulk disconnect, `[add]` auto-discover (+19 specs).

### 14-day gate "warn but submit" posture flipped to hard reject

**What:** D14 originally specified the 14-day title/handle change cooldown gate
as a soft warning — surface the cooldown, but let the form submit if the user
pressed through. D22 flips this to a hard reject — the form is blocked until the
cooldown clears (or the reminder fires).

**Why:** The soft posture defeated the purpose of the gate; users would press
through routinely and burn YouTube's 14-day quota. Pairing the hard reject with
sub-spec 11h's `[remind me on YYYY-MM-DD]` link gives the user a non-frustrating
recovery path while keeping the gate enforceable.

**Where:** commit `5f19aa3`; decisions D14 (original) and D22 (flip).

## Cross-references

- `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
- `docs/realignment-2026-05-09.md`
- `docs/orchestration/follow-ups.md`
- `specs/11-channel-management-and-preview.md`
- `specs/11a-channel-schema-and-sync.md`
- `specs/11h-calendar-reminder-integration.md`
