# Phase 2 — Scope Additions

Scope items added to Phase 2 beyond what the original `02-plan.md` declared.
Each entry includes the rationale.

## citext extension bundled into Phase 2's extensions migration

**Original plan:** `02-plan.md` lists `pgcrypto` and `vector` only. citext was
scheduled in Phase 3.

**Addition:** citext is enabled in the same `enable_postgres_extensions`
migration as pgcrypto and vector.

**Why:** running a second extension-only migration in Phase 3 is pure overhead.
citext at install time is free and is needed by `saved_views.url` immediately
for case-insensitive uniqueness parity with MySQL's default ci collation.

## In-scope bug fix: `create_video.rb` JSON tags coercion

**Original plan:** not mentioned (bug surfaced during pre-implementation audit).

**Addition:** `app/mcp/tools/create_video.rb:29` is updated to split the
comma-separated tags string into an array before assignment to the JSON column.
Spec at `spec/mcp/tools/create_video_spec.rb:30` is updated to assert array
equality.

**Why:** MySQL silently coerced the string into the JSON column; Postgres will
not. The bug surfaces only when the adapter switches. Fixing it as part of Phase
2 prevents a follow-up patch.

## Citext applied narrowly to `saved_views.url`

**Original plan:** Phase 2 had no citext columns; the broader citext rollout was
a Phase 3 item.

**Addition:** `saved_views.url` becomes a `citext` column in this phase. All
other case-insensitive uniqueness validations (YouTube channel/video/playlist
IDs, hex token digests, `app_settings.key`) stay as `string` since their values
are opaque ASCII; their model validators get an explicit
`case_sensitive: false`.

**Why:** the audit confirmed `saved_views.url` is the only column where case
differences would create real-world duplicate rows. Adding citext only where it
matters keeps the migration tight.

## Legacy MySQL credentials and env vars retained until post-verification cleanup

**Original plan:** "remove MYSQL\_\* keys" was implied as part of the cutover.

**Addition:** keep the `:mysql` block in encrypted credentials and `MYSQL_*`
keys in `.env.example` / `.env.development` until the user verifies the Postgres
migration end-to-end. A separate post-verification cleanup pass removes them.

**Why:** rollback insurance during the migration window. Cost is near-zero; the
safety margin is meaningful.

## .env files exclude all secrets — passwords stay in Rails credentials only

**Original plan**: did not specify; implementer included `POSTGRES_PASSWORD` in
`.env.example`, `.env.development`, `.env.test`.

**Addition**: `.env*` files contain only structural keys (`POSTGRES_HOST`,
`POSTGRES_PORT`). Sensitive values (`POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`) live exclusively in
`Rails.application.credentials.dig(:postgres, :*)`. `config/database.yml` reads
sensitive values from credentials only — no `ENV.fetch` fallback for
password/user/database. `docker-compose.yml` uses
`POSTGRES_HOST_AUTH_METHOD: trust` for the local dev container, mirroring the
prior `MYSQL_ALLOW_EMPTY_PASSWORD: "yes"` pattern.

**Why**: matches the legacy MySQL convention (per user correction) and follows
the project rule that secrets never live in committed plain-text files. Captured
as durable feedback memory (`feedback_no_secrets_in_env.md`).
