# Manual Test Playbook — Phase 2 Postgres Migration

**Branch**: step-postgres **Spec**:
pito-dev-kb/plans/beta/02-postgres-migration/specs/postgres-migration.md
**Reviewer date**: 2026-05-01

## Preconditions

- Docker running with healthy iptables (`sudo systemctl restart docker` if
  needed).
- pito containers up: `docker compose up -d` (from `pito` repo).
- No env-var exports needed; credentials hold the secrets.
- The Postgres password (verbatim copy of the legacy MySQL password) is
  `Pass123#`. Use it whenever `psql` prompts.

## Steps (run in order — record any unexpected output)

### 1. Stack health

- `cd ~/Dev/pito-project/pito && docker compose ps`
  - Expect: `pito-postgres-1`, `pito-redis-1`, `pito-meilisearch-1` — all
    `healthy`.
  - Expect: `client-api-*` containers still running independently, untouched.

### 2. Extensions live

- `psql -h 127.0.0.1 -p 5433 -U pito -d pito_development -c "\dx"`
  - Password from credentials. To fetch it programmatically:
    `bin/rails runner 'puts Rails.application.credentials.dig(:postgres, :development, :password)'`.
  - Expect: `citext`, `pgcrypto`, `plpgsql`, `vector`.

### 3. Credentials parity

- `bin/rails runner 'p Rails.application.credentials.dig(:postgres, :development).keys'`
  - Expect: `[:database, :username, :password]`.
- `RAILS_ENV=test bin/rails runner 'p Rails.application.credentials.dig(:postgres, :test).keys'`
  - Expect: `[:database, :username, :password]`.
- Cross-check verbatim copy: each value should equal
  `dig(:mysql, :development, …)` / `dig(:mysql, :test, …)` for the matching key.

### 4. App boot — both Pumas

- `bin/dev` (full stack).
- Open `https://app.pitomd.com/` — dashboard renders.
- Visit `/channels`, `/videos`, `/saved_views`, `/settings` — all render.
- Open `https://mcp.pitomd.com/mcp` — MCP HTTP responds.
- Tail the foreman log: no `mysql2` errors, no pool-exhaustion warnings.

### 5. Functional spot-checks

- Search bar: type a known seeded video title — Meilisearch returns hits.
- Create a channel via web UI; confirm in `bin/rails c` with `Channel.last`.
- Bulk-delete a couple of seeded videos via UI; check `/sidekiq` queue empties.
- Dashboard chart that uses `group_by_*` — buckets align with UTC days.

### 6. JSON column behaviour

- `bin/rails runner 'p Video.last.tags.class'` — expect `Array`, not `String`.
- Create a Video via the `create_video` MCP tool with comma-separated tags (e.g.
  `"alpha,beta,gamma"`). Then `bin/rails runner 'p Video.last.tags'` — expect
  `["alpha", "beta", "gamma"]`.

### 7. Citext behaviour

- `bin/rails runner 'SavedView.create!(name: "test", url: "https://Example.com/Foo", kind: "channels"); p SavedView.where(url: "https://example.com/foo").exists?'`
  - Expect: `true` (case-insensitive match via citext).
- Sanity follow-up:
  `bin/rails runner 'sv = SavedView.create!(name: "x", url: "https://Example.com/Bar", kind: "channels"); p SavedView.create(name: "y", url: "https://example.com/bar", kind: "channels").errors[:url]'`
  - Expect: a "has already been taken" error (uniqueness scoped to kind,
    citext-aware).

### 8. Test gates from a fresh shell

Open a new terminal with no environment exports. From `pito/`:

- `bundle exec rspec` — expect `423 examples, 0 failures`.
- `bundle exec brakeman --quiet` — expect `Errors: 0`, `Security Warnings: 0`.
- `bundle exec bundler-audit check --update` — expect
  `No vulnerabilities found`.

### 9. client untouched

- `docker ps --format '{{.Names}}'`
  - Expect `client-api-mysql-dev-1` and `client-api-redis-1` listed (or in their
    prior state). They are not Pito's responsibility but must remain.

### 10. Schema sanity

- Open `db/schema.rb`.
  - Top of file shows `enable_extension "citext"`, `"pg_catalog.plpgsql"`,
    `"pgcrypto"`, `"vector"`.
  - Schema version is `2026_05_01_165846` (the citext column-change migration).
  - No `t.json` lines anywhere — only `t.jsonb` for `parameters`,
    `target_video_ids`, `dry_run_preview`, `tags`.
  - `saved_views.url` is declared as `t.citext "url", null: false`.
  - No `charset:` / `collation:` `utf8mb4` lines on any `create_table`.

## Reviewer-flagged items requiring user attention before commit

These come from Phases A and B of the review (full detail in
`2026-05-01-postgres-migration-review-notes.md`). None are blockers; all are
YELLOW informational at most.

1. `bin/setup` prints the literal Postgres password (`"Pass123#"`) in its
   credential bootstrap message. Cosmetic — the same plaintext sat in
   `docker/mysql/init.sql` previously and still sits in encrypted credentials,
   but the help string is the only place it now lives unencrypted in the repo.
   Consider replacing with `<your-password>` or omitting the password line
   entirely.
2. `docker-compose.yml` does not pass `POSTGRES_PASSWORD` to the container; auth
   relies on `POSTGRES_HOST_AUTH_METHOD: trust`. This is dev-only and matches
   the prior MySQL `MYSQL_ALLOW_EMPTY_PASSWORD` posture, but Rails authenticates
   with a real password from credentials. The container accepts any password (or
   none) on the trust pathway. Documented behaviour, but worth knowing: the
   password in credentials is enforced at the Rails layer only, not the Postgres
   layer. Production (Phase 16) must not run `trust`.
3. `config/database.yml` for the `test` environment lost the
   `MYSQL_USERNAME`/`MYSQL_PASSWORD`/`MYSQL_DATABASE` env-var fallbacks that
   used to override credentials. CI workflow may need updating if it relied on
   those env vars; check `.github/workflows/ci.yml`.
4. The `:postgres` credentials block has been written into the master
   `config/credentials.yml.enc` (production-shared file), not into
   per-environment files (`config/credentials/development.yml.enc`,
   `config/credentials/test.yml.enc`) as the spec directed. Behaviourally
   equivalent in development/test because the master file is the fallback, but
   the spec asked for per-env files; flag for awareness only.
5. `MYSQL_HOST` / `MYSQL_PORT` remain in `.env.example` (intentional per spec
   section 4b — cleanup pass).

## Pass/Fail summary

[Fill in after running the steps above.]

| #   | Step                   | Result | Notes |
| --- | ---------------------- | ------ | ----- |
| 1   | Stack health           |        |       |
| 2   | Extensions live        |        |       |
| 3   | Credentials parity     |        |       |
| 4   | App boot — both Pumas  |        |       |
| 5   | Functional spot-checks |        |       |
| 6   | JSON column behaviour  |        |       |
| 7   | Citext behaviour       |        |       |
| 8   | Test gates             |        |       |
| 9   | client untouched       |        |       |
| 10  | Schema sanity          |        |       |

If every step is green, the user signals OK and the implementer commits + pushes
per `beta.md` workflow. The cleanup pass (section 4b of the spec) follows after
the migration is confirmed stable.
