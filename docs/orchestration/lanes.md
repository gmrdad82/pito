# Three-Lane Development Model

This document is the authoritative description of how Pito features move from
idea to shipped across the Rails app, the `pito` CLI, and the MCP surface.

## Why lanes exist

Pito ships the same capability across three form factors: a Rails web app, the
`pito` CLI binary at `extras/cli/`, and an MCP tool namespace. If we built each
capability sequentially across all three surfaces, every phase would block on
the slowest surface and we would lose months of calendar time to coordination.

Lanes solve this by making the Rails app the canonical specification. Once a
feature is real in the Rails app — schema, endpoints, channels, views, tests —
the `pito` CLI and the MCP surface can fan out from it in parallel. Each
downstream lane consumes the same JSON contract and ActionCable events; neither
has to wait on the other, and either can opt out of a feature when the form
factor doesn't fit.

The model trades a small amount of double-work (re-implementing UX in two
clients) for a large amount of unblocked parallelism and a single source of
truth.

## Lane 1 — app (Rails)

Lane 1 is canonical. A feature does not exist in Pito until it exists in the
Rails app.

### Lane 1 contract

A Lane 1 feature must include all of the following before any Lane 2 work
begins:

- **Schema** — migrations applied, models with validations and associations.
- **Server logic** — service objects or controller actions covering the full
  feature behavior, including authorization.
- **HTTP surface** — JSON endpoints with stable shapes, documented in
  `pito/docs/`.
- **Realtime surface** — ActionCable channels and broadcast payloads where the
  feature has live-update semantics. If no realtime is needed, the spec says so
  explicitly.
- **Web UX** — ERB views and Stimulus controllers giving the feature a usable
  browser flow.
- **Tests** — RSpec coverage for models, controllers, services, channels, and
  any system-level happy path. Reviewer agent must run green.
- **Docs** — `pito/docs/architecture.md`, `pito/docs/mcp.md` (where relevant),
  and any feature-specific doc updated by the docs-keeper agent.
- **Manual test playbook** — produced by the reviewer agent, stored under
  `orchestration/playbooks/`, exercised by the user before merge.

When all of the above is merged on `main` of the `pito` repo, Lane 1 for that
feature is complete. Only then does Lane 2 spawn.

## Lane 2a — `pito` CLI

Lane 2a mirrors Lane 1 features that make sense in a terminal/Ratatui form
factor inside the unified `pito` CLI binary at `extras/cli/`. It consumes the
JSON endpoints and ActionCable channels defined by Lane 1; it never reaches into
the Rails database directly.

Lane 2a starts after Lane 1 merges and runs in parallel with Lane 2b. It may
complete before, after, or simultaneously with Lane 2b — there is no
synchronization between the two.

## Lane 2b — MCP

Lane 2b mirrors Lane 1 features as MCP tools so an LLM agent can drive Pito
programmatically. Tool definitions live inside the `pito` repo (the MCP server
is part of the Rails app) and consume the same domain models and services Lane 1
produced.

Lane 2b starts after Lane 1 merges and runs in parallel with Lane 2a.

## Parallel rule

Lane 2a and Lane 2b fan out from Lane 1 simultaneously. They do not block each
other. They may complete at different times. They are reviewed and merged
independently.

## Skip-list rule

Either Lane 2 surface may explicitly skip a Lane 1 feature when the form factor
does not fit. A skip is never silent.

To record a skip:

1. Add a one-line addendum to the relevant ADR in `decisions/` (typically
   `0002-app-first-then-terminal-mcp-parallel.md`) referencing the skipped
   feature and the lane skipping it.
2. The architect-spec agent must mention the skip in the feature spec under an
   explicit "Lane 2 scope" section.
3. The docs-keeper agent records the skip in the phase log under
   `docs/plans/beta/<phase>/log.md`.

A canonical example: server-side video uploads are skipped in both Lane 2a and
Lane 2b because uploads happen entirely browser-side via the YouTube Data API
client SDK. See `decisions/0001-no-server-side-uploads.md`.

## Role discipline cross-reference

The lane model defines WHERE work lands (Lane 1 app, Lane 2a `pito` CLI, Lane 2b
MCP). Role discipline (`orchestration/agents.md` → "Role discipline") defines
WHO does each kind of work within those lanes. The two are orthogonal — every
lane has every role; an implementer in Lane 2a is still an implementer with the
same role boundaries as one in Lane 1.
