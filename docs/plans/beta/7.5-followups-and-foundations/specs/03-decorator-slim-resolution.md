# Phase 7.5 — Step 03 — Decorator Slim Resolution

> Decision-only spec. Resolves the Phase 7.5 question raised by the Phase 6+7+A2
> reviewer playbook: should `ChannelDecorator` and `VideoDecorator` be slimmed
> to match Path A2's thin model shapes, or kept as-is with derived/joined
> fields?

---

## Goal

Settle the open question captured in `docs/orchestration/follow-ups.md` under
"Decorator slim question — re-evaluate Channel/Video summary JSON shape
post-Path-A2", land the resolution, and close the entry in `follow-ups.md`'s
`## Done` section with the resolving commit hash.

This is most likely a **no-code spec** — the master agent's lean is "keep
decorators as-is", and the user is expected to confirm. If the user flips the
decision, this spec converts to a real implementation spec dispatched to the
rails-impl agent (with a paired cli-impl dispatch to align Rust structs).

## Background

Path A2 retracted `Channel` and `Video` to thin YouTube-reference records:

- `Channel`:
  `id, tenant_id, channel_url, star, oauth_identity_id, last_synced_at, timestamps`.
- `Video`:
  `id, tenant_id, youtube_video_id, channel_id, star, oauth_identity_id, last_synced_at, timestamps`.

The decorators emit a wider wire shape than the model carries:

- `ChannelDecorator#as_summary_json` emits a **derived** `connected` field
  (computed from `oauth_identity_id.present?`).
- `VideoDecorator#as_summary_json` emits **joined-aggregate** fields (`views`,
  `likes`, `comments`, `watch_time_minutes`, `trend`) computed from the
  surviving `video_stats` table.

The CLI's matching Rust structs in `extras/cli/src/api/models.rs` were aligned
to the wire shape, not the model.

## The question

Should the decorators be slimmed to literal model parity (drop `connected`, drop
the video-stats aggregates), or kept as-is?

## Master agent's lean (default — Q5 = "keep")

**Keep decorators as-is.**

Rationale:

- Path A2 was about not pre-committing to a YouTube-metadata cache — i.e. don't
  store a column the user didn't ask for. Aggregating computed values from
  intentional sources (`oauth_identity_id` presence; the surviving `video_stats`
  table) is a different concern.
- The aggregates are cheap (one join per request, indexed). Removing them would
  force every consumer (web pane, MCP tool, CLI struct) to re-aggregate, which
  is a wash at best and a regression on the MCP surface (the tool would either
  lose the field or duplicate the query).
- The `connected` boolean is the cleanest way to surface oauth state to
  consumers without leaking the FK; renaming the column to a derived "is
  connected" field across two surfaces is friction the user didn't ask for.

If the user confirms (Q5 = keep), this spec lands as **a no-code documentation
update**:

- Move the `follow-ups.md` "Decorator slim question" entry from `## Open` to
  `## Done` with a one-line resolution: "kept as-is — decorators aggregate
  intentional values; Path A2's storage retract does not propagate to the API
  surface". Add the resolving commit hash (which is whatever commit hoists the
  resolution into the follow-ups doc — a docs-keeper dispatch handles the move).
- No spec / model / decorator / Rust changes.

If the user flips (Q5 = slim):

- This spec becomes a real implementation spec. The slim takes:
  - `ChannelDecorator#as_summary_json`: drop `connected` from the payload. Wire
    consumers query `oauth_identity_id` directly OR compute the "connected"
    presence themselves.
  - `VideoDecorator#as_summary_json`: drop `views`, `likes`, `comments`,
    `watch_time_minutes`, `trend`. Consumers query `/videos/:id/stats.json` (or
    the equivalent) for aggregates.
  - Rust structs in `extras/cli/src/api/models.rs` collapse to match.
  - Every CLI screen consuming the dropped fields adjusts (videos list `views`
    column gone; channels list `connected` column re-derived from a separate API
    call OR dropped).
  - MCP tool outputs collapse.
  - All affected specs and CLI tests rewrite.

The flip is a 2-dispatch effort (rails + cli) and would be a real spec under a
separate slug if the user picks it. This file remains the decision record either
way.

## Files touched (Q5 = keep — default)

- None at code level. The `follow-ups.md` entry move is the docs-keeper's
  responsibility post-resolution.

## Files touched (Q5 = slim — alternative)

- `app/decorators/channel_decorator.rb` — slim `as_summary_json` and
  `as_detail_json` if present.
- `app/decorators/video_decorator.rb` — same.
- `extras/cli/src/api/models.rs` — drop the dropped fields from `Channel` and
  `Video` structs.
- Affected CLI UI files: `ui/channels.rs`, `ui/channel_detail.rs`,
  `ui/videos.rs`, `ui/video_detail.rs`, `ui/search.rs`. Drop dropped columns /
  fields.
- Affected MCP tools: `app/mcp/tools/list_channels.rb`, `list_videos.rb`,
  `get_channel.rb`, `get_video.rb`. Update description + output payload.
- Specs: every spec asserting the dropped fields. Rewrite.
- `docs/architecture.md` — update the "Channel / Video schema philosophy
  (post-Path-A)" subsection if the wire shape changes affect documented
  contracts.

The flip implementation spec lands as a separate slug
(`03b-decorator-slim-implementation.md` or similar) — this file remains the
decision-only resolution.

## Acceptance

(Q5 = keep — default)

- [ ] User confirms Q5 = keep.
- [ ] `follow-ups.md` "Decorator slim question" entry moves to `## Done` with
      the resolution: "kept as-is — decorators aggregate intentional values from
      oauth presence and the surviving `video_stats` table; Path A2's storage
      retract does not propagate to the API surface".
- [ ] No code changes.

(Q5 = slim — alternative; this spec spins out into the implementation spec and
the acceptance lives there.)

## Manual test recipe

(Q5 = keep — default)

- None. Documentation-only change; the existing manual playbooks cover the
  unchanged surfaces.

(Q5 = slim — alternative)

1. After the slim ships, `curl -s http://localhost:3000/channels.json | head`
   shows the slimmed payload (no `connected` field).
2. `pito` CLI launched against the running server populates the channels panel
   without deserialization errors.
3. Existing Phase 6/7 manual playbook walks pass without regression.

## Cross-stack scope

(Q5 = keep) — none.

(Q5 = slim) —

- Rails — **in scope.**
- `pito` CLI — **in scope.**
- MCP — **in scope.**
- Cloudflare Pages website — **out of scope.**

## Open questions

- **Q5** (from `00-phase-overview.md`) — keep decorators as-is, or slim to
  literal model parity? Default = keep.

## Follow-ups created

(Q5 = keep) — none.

(Q5 = slim) — none expected; the implementation spec captures all the work.

## Decisions (locked)

- **No mid-flight deferral.** This spec resolves the question one way or the
  other. It does not bounce the decision into another phase.
- **The decision lives in `follow-ups.md`'s `## Done` section.** Per the
  project's "decisions live in `log.md` by default; ADRs are for durable
  artifacts" convention, a routine "keep this" choice is a follow-up close-out,
  not an ADR.
