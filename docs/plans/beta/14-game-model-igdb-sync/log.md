# Phase 14 — Game Model Expansion + IGDB Sync + Steam-Shelf UI

> **Status:** specs landing 2026-05-10. Implementation pending.
>
> **Realignment work unit:** 6.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; work unit 6
>   ("Game model expansion + IGDB sync") plus Mobile note 4 framing.
> - `docs/notes/2026-05-09-18-54-00-game-model-igdb.md` — Mobile note 4. Source
>   of truth for the Game data model, IGDB API v4 surface, bundles, composite
>   covers, Steam-shelf UX.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install posture; flat storage paths; no `tenant_id` on any new table.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline this phase builds on.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12 / work unit 4. Establishes `videos.project_id`, the writable
>   subset, and the convention for cross-resource link tables. Phase 14 adds the
>   `video_game_link` table that Note 1 mentions but Phase 12 explicitly defers
>   ("Game ↔ Video links — work unit 6 / Phase 14" in Phase 12 §"Out of scope").

## Specs in this phase

This phase ships as three feature specs to keep each implementation lane
self-contained and reviewable:

1. `specs/01-data-model-and-igdb-client.md` — schema (games + reference
   tables), IGDB v4 client, Twitch OAuth credentials, on-demand sync,
   nightly refresh, last-write-wins semantics.
2. `specs/02-bundles-and-composite-covers.md` — bundle model, bundle
   members, composite cover builder via libvips, on-disk storage at flat
   `composites/` path, regen triggers.
3. `specs/03-steam-shelf-ui-and-video-game-links.md` — Steam-shelf-style
   listing UI for games and bundles, the `video_game_link` join table, MCP
   + CLI coverage matrix.

Each spec carries its own acceptance / test sweep / manual playbook.

## Next

Master agent dispatches `pito-rails-impl` against the three specs in order
once the user signs off. Spec 1 is the foundation (Spec 2 adds composite
covers on top of Spec 1's models; Spec 3 surfaces both via UI / cross-
links).

## Sessions

(empty — appended after the user validates each implementation pass)
