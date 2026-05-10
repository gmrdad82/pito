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

## Cross-references

- `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
- `docs/realignment-2026-05-09.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md`
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md`
