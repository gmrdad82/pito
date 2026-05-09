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

## Cross-references

- `docs/realignment-2026-05-09.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md`
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md`
