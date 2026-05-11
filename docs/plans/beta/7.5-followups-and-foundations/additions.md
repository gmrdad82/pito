# Phase 7.5 — Follow-ups Sweep + Concept Foundations · Additions

> Items added to this phase's downstream backlog by the 2026-05-09 realignment.
> See `docs/realignment-2026-05-09.md` for the top-level direction map.

## 2026-05-09 — Realignment work units routed via follow-ups

The 2026-05-09 realignment introduces a sequence of large work units (tenant
drop, MCP scope simplification, Channel + Video edit surfaces, Analytics, Game
model, Calendar, Notifications, CLI parity) that are NOT scoped into Phase 7.5
itself but are the immediate downstream from this phase's wrap-up.

Phase 7.5 does NOT change shape — its tracks and specs stay as defined. The
realignment's work units land as new specs / phases downstream of 7.5, with the
tenant drop dispatch as the first concrete spec after 7.5 closes.

### Tenant drop (next dispatch)

The 2026-05-09 realignment commits to dropping tenants entirely (ADR 0003). The
unwind is large and is the first new spec to land downstream of Phase 7.5.

**Where it lives:** TBD by user (open question 8 in
`docs/realignment-2026-05-09.md`). Likely in a new phase folder named either
`08-tenant-drop` (if phase numbering continues sequentially) or under a thematic
folder named after the realignment work unit.

### MCP scope simplification (after tenant drop)

ADR 0004's commitment becomes code immediately after the tenant drop lands.
Likely a small dispatch (~2-3 hours) under the same phase or adjacent.

### Per-domain spec dispatches (after foundation work)

Channel data sync + edit surface; Video schema expansion + edit surface +
pre-publish checklist; Analytics sync engine + tables + dashboard; Game model
expansion + IGDB sync; Calendar; Notifications; MCP tool catalog expansion; CLI
parity. Each gets its own architect- spec dispatch in the order specified in the
realignment doc.

## 2026-05-10 — Final reconciliation

Phase 7.5 closes with **no items added to the phase itself** by the 2026-05-09
realignment. Every realignment work unit lands as a downstream phase / spec, NOT
as a retroactive Phase 7.5 line item. The phase's original tracks (A · B · C)
shipped as scoped; the realignment sets up the work that follows 7.5, not work
that joins it.

Two in-flow dispatches landed during the Phase 7.5 window without their own
numbered specs (MCP OAuth + bearer dispatch, Doorkeeper polish + OAuth UI
polish, Doorkeeper consent restyle, MCP icon discovery). They are not phase
additions — they are bundled in the close-out reconciliation table under
"In-flow work outside the original plan" rather than rewriting `plan.md`.

- **Item:** none — phase closes with original scope intact.
- **Rationale:** realignment work units are downstream phases; in-flow
  dispatches are tracked in the close-out reconciliation, not as plan additions.
- **Plan link:** none.
- **Driver:** Phase 19 close-out spec
  (`docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`).

## 2026-05-11 — Step 11 sub-spec 11h (calendar reminder integration)

**What:** Added sub-spec `specs/11h-calendar-reminder-integration.md`. The
14-day title/handle gate now fires a `[remind me on YYYY-MM-DD]` link that
silently auto-creates a calendar entry tied to the eligibility date instead of
leaving the user to thread the reminder through a separate surface.

**Why:** User directive resolving D19 / Q1 — the cooldown gate is the moment the
user feels the pain, so the reminder must be one click away from that gate and
auto-bound to the right date. No separate calendar form.

**Where:** commit `fda1294` (Phase 7.5 sub-spec 11h: calendar reminder
integration, 242 lines, 5 open questions); sub-spec file
`specs/11h-calendar-reminder-integration.md`.

## 2026-05-11 — Step 11 sub-spec 11i (daily diff check and resolution)

**What:** Added sub-spec `specs/11i-daily-diff-check-and-resolution.md`. A daily
Sidekiq cron checks every connected channel's local fields against the YouTube
live state, persists the diffs, and surfaces a bidirectional resolution page
(push local → YouTube, or pull YouTube → local, per field).

**Why:** Resolution of Q7 layered onto D11 + D20 — the user wants pito to notice
drift without requiring a manual sync, AND wants the resolution surface to
choose direction per field rather than always overwriting one side.

**Where:** commit `c1cfca5` (Phase 7.5 sub-spec 11i: daily diff-check cron +
resolution page, 664 lines, 8 open questions); sub-spec file
`specs/11i-daily-diff-check-and-resolution.md`.

## Cross-references

- `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
- `docs/realignment-2026-05-09.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md`
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md`
- `specs/11h-calendar-reminder-integration.md`
- `specs/11i-daily-diff-check-and-resolution.md`
