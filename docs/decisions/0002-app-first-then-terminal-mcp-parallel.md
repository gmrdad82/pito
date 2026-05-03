# ADR 0002 — App First, Then Terminal and MCP in Parallel

## Status

Accepted

## Context

Pito ships the same product capability across three surfaces: a Rails web app, a
terminal app (`pito-sh`), and an MCP tool namespace. We need a sequencing rule
that lets us move fast without producing three forks of the same feature
drifting apart.

Two failure modes were considered and rejected:

- **All three in parallel from day one.** No source of truth. Schemas drift,
  JSON shapes drift, behavior drifts. The cost of reconciling later exceeds the
  cost of any individual feature.
- **All three sequentially.** Every phase blocks on the slowest surface.
  Calendar time dominates the project plan. Terminal and MCP work pile up behind
  Rails work that has long since been validated.

We want one canonical surface and parallelism on the rest.

## Decision

Lane 1 (Rails app) is canonical. Every new capability is built first as Rails:
ERB views, Stimulus controllers, JSON endpoints, ActionCable channels where
realtime applies. The Rails app is the source of truth for schema, behavior, and
contracts.

Lane 1 must land — merged on `main` of the `pito` repo, with tests green and
docs updated — before Lane 2 starts.

Lane 2a (`pito-sh` terminal app) and Lane 2b (MCP tool surface) fan out from
Lane 1 and run **in parallel**. Either Lane 2 surface may explicitly skip a
feature when the form factor doesn't fit. A skip gets a one-line addendum to
this ADR (or a more specific ADR) referencing the feature, with rationale; skips
are never silent.

## Consequences

- **No Lane 2 work begins before Lane 1 merges.** This is enforced by the
  architect's spec, not by tooling. The architect-spec agent refuses to brief
  pito-sh-impl or pito-mcp until the corresponding Lane 1 spec is closed.
- **Lane 2a and Lane 2b run on independent timelines.** They may complete on
  different days. They are reviewed and merged independently. There is no
  synchronization point between them.
- **Every Lane 1 feature ships a JSON + ActionCable contract.** This is the
  surface Lane 2 consumes. The contract is documented in
  `pito/docs/architecture.md` and `pito/docs/mcp.md`.
- **Skip-list is durable.** Skips appear in this ADR or a child ADR, in the
  feature spec under `docs/plans/beta/<phase>/`, and in the phase log. An
  audit-state pass can reconstruct the full Lane 2 coverage at any point in
  time.
- **Some double-implementation is accepted.** The same logical feature is
  implemented twice in client UX (TUI and MCP tool wiring). This is the cost
  paid for parallelism and a single source of truth, and it's smaller than the
  cost of drift.

## Skip-list addenda

This list grows as features are explicitly skipped on a Lane 2 surface. Format:
feature, lane skipped, ADR or rationale.

- **Server-side video uploads** — skipped on Lane 2a (`pito-sh`) and Lane 2b
  (MCP). See `decisions/0001-no-server-side-uploads.md`.

## Date

2026-04-29

## Related

- `orchestration/lanes.md` — full description of the three-lane model
- `orchestration/agents.md` — agent catalog enforcing the lane sequencing
- `decisions/0001-no-server-side-uploads.md` — first applied skip
