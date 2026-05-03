# Phase 2 — Postgres Migration · Session Log

## 2026-05-01 — Pre-implementation kickoff

**State at start:** pito repo on `main`, MySQL 8 container running
(`pito-mysql-1`), no Postgres infrastructure yet, all current data is seed-only
(no preservation needed).

**Decisions captured before execution:**

- citext bundled into Phase 2 (with pgcrypto + vector) — single extensions
  migration. Phase 3's citext line item is fulfilled here.
- Scope is Lane 1 only — no pito-sh or MCP work (Phase 2 is pure
  infrastructure).
- Postgres credentials mirror MySQL credentials: same per-env credential files,
  sibling `:postgres` block, values copied verbatim. Legacy `:mysql` block stays
  until post-verification cleanup.
- Pre-existing JSON column type `t.json` swapped to `t.jsonb` in two existing
  migrations (videos.tags,
  bulk_operations.{parameters,target_video_ids,dry_run_preview}) — change
  applied at the migration files so the regenerated schema is correct from the
  start.
- In-scope bug fix: `app/mcp/tools/create_video.rb` was passing a
  comma-separated string into a JSON column; matching spec asserted the broken
  behavior. Fixed in Phase 2.
- Citext applied narrowly: only `saved_views.url` becomes citext. Opaque YouTube
  IDs and hex digests remain as standard strings; their model-side validators
  must declare `case_sensitive: false` explicitly.

**Safety constraints recorded:**

- External resources to NEVER touch: `client-api-mysql-dev-1`,
  `client-api-redis-1`, `client-api_default` network, two anonymous volumes
  (sha256 ids ad833d... and b8e152...), Docker built-in networks.
- Pito-owned but KEEP RUNNING: `pito-redis-1`, `pito-meilisearch-1`, their named
  volumes, `pito_default` network.
- Pito-owned destruction targets (require STOP-and-confirm): `pito-mysql-1`,
  `pito_mysql_data`, `pito/docker/mysql/init.sql`.

**Audits run pre-implementation:**

- MySQL idiom audit on pito codebase — 41 findings.
- Docker resource enumeration — client collision risk identified, drove the
  don't-touch list above.
- RSpec MySQL-coupling audit — 1 substantive bug (the create_video JSON coercion
  above), otherwise clean.

**Next entry will record:** implementer execution results, spec pass/fail,
manual test handoff.

## 2026-05-01 — Implementation complete (pre-commit)

**Outcome**: 423 RSpec examples passing, Brakeman clean, bundler-audit clean.
Branch `step-postgres` is ready for user manual validation per the playbook at
`pito-dev-kb/orchestration/playbooks/2026-05-01-postgres-migration.md`.

**Notable mid-flight catches**:

- Three `CAST(... AS SIGNED)` patterns in controllers and an MCP tool —
  MySQL-specific casts not surfaced by the pre-implementation audit. Replaced
  with `CAST(... AS BIGINT)`.
- `.env` password placement — implementer initially put `POSTGRES_PASSWORD` in
  `.env*`. User flagged that legacy MySQL kept passwords exclusively in Rails
  credentials; corrected via a follow-up pass. Pattern documented as durable
  feedback memory and as Addition entry.
- Docker iptables chain corruption on host — required
  `sudo systemctl restart docker` to rebuild. During the corruption window, the
  compose file used `network_mode: host` as a workaround; reverted to bridge
  networking after the daemon restart.

**Resources state**: pito-postgres-1, pito-redis-1, pito-meilisearch-1 healthy.
client-api-\* untouched. pito_postgres_data, pito_redis_data,
pito_meilisearch_data persisted across the network revert.

**Next**: user validates manually using the playbook. On green, the architect
commits + pushes step-postgres. Post-verification cleanup (per spec section 4b)
removes the legacy `:mysql` credentials block and `MYSQL_*` env keys in a
follow-up pass.
