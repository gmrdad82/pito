# Phase 14 Spec 02/03 — Security audit (2026-05-10)

**Branch:** `main`  
**Specs:** `docs/plans/beta/14-game-model-igdb-sync/specs/02-bundles-and-composite-covers.md`,
`docs/plans/beta/14-game-model-igdb-sync/specs/03-steam-shelf-ui-and-video-game-links.md`  
**Reviewer
playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-14-spec-02-and-03-bundles-and-steam-shelf.md`

## Verdict

CLEAR TO MERGE. No critical or high findings.

## Findings

### F1 — IGDB Client HTTP timeouts unset (MEDIUM)

`app/services/igdb/client.rb:236-246` — `Net::HTTP.post` runs at gem-default
60s. Same pattern as Phase 12 F1 / Phase 16 F2. Wrap in `Net::HTTP.start` with
`open_timeout=5, read_timeout=10, write_timeout=5`.

### F2 — Composite::TileCache HTTP timeouts unset (MEDIUM)

`app/services/composite/tile_cache.rb:45-53` — same root cause. Same fix.

### F3 — Composite cover pipeline lacks Content-Type / size / pixel-bomb guards (LOW, defense-in-depth)

After F2 fix, also: validate `Content-Type` starts with `image/jpeg`, cap
response body to 5 MB, add max-pixel guard before `thumbnail_image`.

### F4 — IGDB raw response body propagates to user-visible error envelopes (LOW, info disclosure)

`app/services/igdb/client.rb:269` interpolates full response body into
`flash[:alert]` and MCP error responses. Truncate to 200 chars or use a static
error-message map.

### F5 — Bundle.igdb_source_id lacks numericality validation (LOW, DoS)

Non-positive id triggers unrescued ArgumentError 500. Add
`numericality: { only_integer: true, greater_than: 0, allow_nil: true }`.

### F6 — IGDB search query string unbounded (informational)

`Mcp::Tools::IgdbSearch` — cap `q` to 256 bytes, reject control chars.

## Out-of-scope but noted

- `config.force_ssl` disabled (Brakeman flag); follow-up before Hetzner deploy
- `Game#cover_image_id` no format validator (future-proofing)
- `/composites/:filename.jpg` no CSP header

## Quality gates

- Brakeman strict: 0 new warnings
- bundler-audit: clean
- ruby-vips 2.3.0 + libvips 8.18.2 — no pinned advisories

## Severity table

| Severity      | Count | IDs        |
| ------------- | ----- | ---------- |
| Critical      | 0     | —          |
| High          | 0     | —          |
| Medium        | 2     | F1, F2     |
| Low           | 3     | F3, F4, F5 |
| Informational | 1     | F6         |

## Action

F1 + F2 fix-forward dispatched 2026-05-10 21:35.
