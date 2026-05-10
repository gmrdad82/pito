# Phase 14 — Game model + IGDB sync — Closed (2026-05-10)

## Goal

Game model with IGDB metadata sync, bundles + composite covers (libvips),
Steam-shelf UI, video↔game/bundle links, MCP tools (16+1).

## Status

DONE. All 3 specs in main + Spec 02/03 reviewer + security audit + F1+F2
fix-forward + Igdb::TokenCache third-path follow-up.

## Links

- Specs: `docs/plans/beta/14-game-model-igdb-sync/specs/{01,02,03}-*.md`
- Reviewer playbook:
  `docs/orchestration/playbooks/2026-05-10-phase-14-spec-02-and-03-bundles-and-steam-shelf.md`
- Security playbook:
  `docs/orchestration/playbooks/security-2026-05-10-phase-14-spec-02-and-03-bundles-and-steam-shelf.md`
- Phase log: `docs/plans/beta/14-game-model-igdb-sync/log.md`

## Key changes

- Game model + IGDB hydration via Twitch OAuth → IGDB v4
- Bundles model + composite covers (libvips multi-tile join)
- /composites/:filename auth-gated route + path traversal guard
- video_game_link + 16 MCP tools (game CRUD/seed, bundle CRUD/seed, link/unlink)
- Steam-shelf views; game show: 3-pane row (cover .pane--narrow + details
  .pane--game-detail + sync + linked videos)
- IGDB main-game category filter (0,8,9,11) by default; opt-out
  `include_editions: yes`
- IGDB outbound HTTP timeouts on Client + TileCache + TokenCache (5/10/5)

## Validation

Walk reviewer playbook; press `i` to open IGDB modal; search a known game; click
[add]; verify cover thumbnails; verify [update] over existing game opens
overwrite confirm.

## Open follow-ups

- F3 (composite cover libvips guards) — defense-in-depth; queued
- F4 (IGDB error truncation) — minor; queued
- F5 (Bundle igdb_source_id numericality) — minor; queued
- F6 (IGDB search query length cap) — informational; queued
