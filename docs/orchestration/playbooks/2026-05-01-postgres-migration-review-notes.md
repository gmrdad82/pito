# Phase 2 Postgres Migration — Reviewer Notes

**Branch**: step-postgres **Reviewed**: 2026-05-01 **Diff stat**: 29 files
changed, 299 insertions(+), 83 deletions(-) **Diff range**: working tree on
`step-postgres` (uncommitted) vs. `main`

---

## Phase A — Code review findings

### A.1 Bugs / regressions

1. **CI workflow not updated.** `.github/workflows/ci.yml` still provisions a
   `mysql:8` service with `MYSQL_*` env vars and uses `mysql2` adapter at
   runtime. The Gemfile no longer ships `mysql2`. CI will fail on the first run
   after this branch lands. The spec does not list `ci.yml` in section 3 ("Files
   touched"), so the implementer was not contracted to fix it — but the spec's
   acceptance criterion "`bin/bundler-audit` is clean" and the broader gate
   suite imply CI passes too. This is a real, blocking gap. Fix is small (swap
   the service block to `pgvector/pgvector:pg17`, swap the env vars, drop
   `MYSQL_DATABASE` override that doesn't exist on the Postgres side). Flag for
   an in-scope fix or an explicit ack-and-defer.

2. **`config/database.yml` lost the test-env env-var override path.** Pre-diff
   `test:` block read `MYSQL_DATABASE`/`MYSQL_USERNAME`/`MYSQL_PASSWORD` env
   vars before falling back to credentials. Post-diff `test:` block reads
   credentials only. CI relied on those env vars (it still sets them today).
   Once CI is migrated to Postgres, equivalent
   `POSTGRES_DATABASE`/`POSTGRES_USERNAME`/`POSTGRES_PASSWORD` overrides are
   likely needed unless CI is reworked to use master.key + credentials. Either
   way, the override path was silently dropped — flag.

3. **`config/credentials.yml.enc` got the `:postgres` block, not per-environment
   files.** Spec section 3 directs the implementer to write to
   `config/credentials/development.yml.enc` and
   `config/credentials/test.yml.enc`. The repo doesn't have those files — only
   the master `config/credentials.yml.enc` exists, and the existing `:mysql`
   block lives there. The implementer correctly followed the project's existing
   convention (sibling `:postgres` block in the same master file with
   `development:`/`test:` sub-keys). Net effect is identical for development and
   test. Flag as a spec-vs-reality mismatch only — no action needed.

4. **`bin/setup` prints the literal Postgres password (`"Pass123#"`) in
   plaintext** in the credential bootstrap message (`bin/setup:48,53`). Pre-diff
   `bin/setup` printed empty strings (the legacy MySQL setup used empty password
   locally). The new code embeds the actual Postgres password from
   `docker-compose.yml`'s default user. Since the same plaintext sat in the
   deleted `docker/mysql/init.sql` and still sits in encrypted credentials, the
   leak surface is unchanged in repo terms — but the help string is now the only
   place it lives unencrypted in the repo. Cosmetic; replace with
   `<your-password>` or a one-liner pointing at `docker-compose.yml` defaults.

5. **No new bugs surfaced in the Ruby code.** Spot-checked the three
   `CAST(... AS BIGINT)` swaps (deletions controller, videos controller,
   list_videos MCP tool); the create_video JSON tags coercion fix (now splits on
   comma, strips, rejects blanks, matches updated spec assertion); the five
   `case_sensitive: false` additions; the timezone pin in `application.rb`. All
   look correct.

### A.2 Dead code

1. **`docker-compose.yml` line 1 carries a dated comment**:
   `# Bridge networking restored after Docker iptables rebuild on 2026-05-01.`
   This is debugging context from the workaround-and-revert episode. Once the
   migration is committed, the comment loses load-bearing meaning — a future
   reader sees a comment about an event they cannot situate. Recommend dropping
   it (or moving to `log.md`).

2. **`config/credentials.yml.enc`: the `:mysql` block remains alongside
   `:postgres`.** Intentional per spec section 4b — left in place during the
   rollback window. Not dead code yet; will be removed in the cleanup pass. Flag
   for completeness only.

3. **`.env.example`: `MYSQL_HOST`/`MYSQL_PORT` retained.** Same: intentional per
   section 4b.

4. **`CLAUDE.md`'s configuration-strategy section** documents both the Postgres
   reality and the legacy MySQL keys-still-present detail. Once cleanup happens,
   the parenthetical "during the Phase 2 cutover window" sentence becomes dead.
   Track for the cleanup pass.

### A.3 Missing tests

1. **Spec `spec/db/extensions_spec.rb` exists and asserts the three extensions**
   — meets the spec.

2. **No spec asserts the new `saved_views.url` citext column behaves
   case-insensitively at the DB level.** The shoulda matcher
   `validate_uniqueness_of(:url).scoped_to(:kind).case_insensitive` in
   `spec/models/saved_view_spec.rb:9` already passed under MySQL collation;
   under Postgres + citext it now passes for the right reason, but a direct
   DB-level assertion (`SavedView.where(url: ...).exists?` with mixed case) is
   missing. Spec section 4a's checklist item "shoulda-matcher specs for all five
   remain green under Postgres" is met for the five legacy models, but
   `saved_views` was the one model that _also_ got a column-type change and
   deserves a dedicated case-insensitivity assertion. Recommend adding a
   one-line `it` in `saved_view_spec.rb` or a new spec under `spec/db/`.

3. **No spec for the citext column-change migration itself.** Low-value to add
   (Rails covers `change_column` mechanics); listing for completeness.

4. **No new MCP Puma DB-smoke spec was added.** Spec section 3 says "create or
   reuse" — existing MCP tool specs (e.g. `spec/mcp/tools/list_videos_spec.rb`)
   already exercise DB reads end-to-end, so the implementer correctly chose
   reuse. The phase log doesn't yet list which existing specs cover this gate —
   a one-liner in `log.md` would close that loop.

5. **No new Web Puma DB-smoke spec was added.** Same — existing controller specs
   cover this. Same one-liner suggestion for `log.md`.

### A.4 Inconsistencies

1. **`docs/setup.md:34` says** "add a `:postgres` block alongside the existing
   `:mysql` block" while `docs/architecture.md:29` calls the `:mysql` block
   "retained until the post-verification cleanup pass." Both are correct, but a
   reader of `setup.md` alone might assume the `:mysql` block is permanent.
   Minor; one-line edit could cross-link.

2. **`docs/setup.md:67` mentions** "Optional: set a single `DATABASE_URL`
   instead of discrete keys (commented in `.env.example`)." The current
   `.env.example` does NOT have a commented `DATABASE_URL` line. Spec section 3
   said "Optionally also document `DATABASE_URL`" — the doc claims it was
   documented but the env example doesn't carry it. Either add the commented
   line or remove the mention from `setup.md`.

3. **`bin/setup`'s help message hardcodes `password: "Pass123#"`** while
   `docs/setup.md`'s example block uses the same literal. Consistent with each
   other; the cosmetic leak (item A.1.4) is the only concern.

4. **`docker-compose.yml` healthcheck uses `127.0.0.1` for Meilisearch** but
   `localhost` was used pre-diff. The change is fine (more deterministic on
   dual-stack hosts), but it's an unrelated drive-by edit — not in the spec's
   scope. Flag.

### A.5 Security cross-references

1. **`POSTGRES_HOST_AUTH_METHOD: trust`** in `docker-compose.yml`. Dev-only;
   matches the prior `MYSQL_ALLOW_EMPTY_PASSWORD: "yes"` posture. Production
   (Phase 16) must explicitly disable trust. Not a Phase 2 issue.

2. **Plaintext password in `bin/setup`** — see A.1.4.

3. **Brakeman clean** — see Phase C.

4. **bundler-audit clean** including the new `pg` gem — see Phase C.

5. Defer to security-auditor for deeper passes (credential rotation policy,
   master.key handling).

### A.6 Plan vs reality

**Delivered as specified:**

- MySQL → Postgres swap in `docker-compose.yml`, `Gemfile`, `database.yml`.
- `pgvector/pgvector:pg17` image; port `5433`.
- `enable_postgres_extensions` migration with `pgcrypto`, `citext`, `vector`.
- `t.json` → `t.jsonb` in two existing migrations.
- Five model `case_sensitive: false` additions.
- `create_video` JSON tags coercion bug fix + spec update.
- Timezone pin in `application.rb`.
- `bin/setup` and `bin/dev` updates.
- `docs/architecture.md` and `docs/setup.md` Postgres sections.
- `CLAUDE.md` tech-stack line update.
- Extensions spec.
- `.env.example` POSTGRES*\* keys with MYSQL*\* retained.
- `:mysql` credential block retained (rollback window).

**Beyond spec (kept — good catches):**

- Three `CAST(... AS SIGNED)` → `CAST(... AS BIGINT)` swaps in
  `deletions_controller`, `videos_controller`, `list_videos`. Spec only
  mentioned `update_all` `LIMIT` and similar in section 8; the implementer found
  and fixed these portably. Each carries a comment naming the original MySQL
  idiom — matches the spec's "one-line comment" rule in section 3.
- Dedicated citext column-type migration (`change_saved_views_url_to_citext`).
  Spec section 4a says `saved_views.url` becomes citext; the implementer
  correctly used a separate migration rather than inline in the extensions
  migration so re-running `db:migrate` against an already-extended DB still
  works.

**Gaps (not delivered):**

- `.github/workflows/ci.yml` not updated. See A.1.1. Real gap; spec didn't list
  it but acceptance criteria implicitly require it.
- `02-plan.md` checkboxes still all unticked. Spec step 23 says "tick
  checkboxes." Per the architect's brief this is "expected" at review time —
  flag for completeness only.
- `log.md` not yet appended with execution-side entry. Spec step 23. Same
  expected-at-review-time note.
- `pito-dev-kb/plans/beta/03-auth-foundation/03-plan.md` not updated to remove
  the duplicated `enable_extension :citext` checkbox. Spec section 3. Cross-repo
  doc edit; flag for the architect.

---

## Phase B — Simplification recommendations

These are recommendations only. The reviewer does NOT touch code in `pito/`.

1. **`docker-compose.yml:1` — drop the dated workaround comment.** The comment
   "Bridge networking restored after Docker iptables rebuild on 2026-05-01" is
   operational history that belongs in `log.md`, not in a service config that
   will be read by every future contributor. Comments should explain WHY the
   file is the way it is, not document past fixes.

2. **`docker-compose.yml` postgres service — set `POSTGRES_PASSWORD`
   explicitly** instead of relying on `POSTGRES_HOST_AUTH_METHOD: trust`. Today
   the container accepts any password (or none). Rails authenticates with the
   real password from credentials, but the divergence between "Postgres trusts
   everything" and "Rails sends Pass123#" is non-obvious. Spec section 3 says
   `POSTGRES_PASSWORD` should be in the env block. Two-line change; matches the
   principle of least surprise.

3. **`bin/setup:46-58` — collapse the help block.** The block prints six `puts`
   lines hardcoding `pito_development`, `pito_test`, `pito`, and `Pass123#`.
   Same values are in `docker-compose.yml` defaults and `docs/setup.md`. A
   one-liner pointing at `docs/setup.md` would be lower-maintenance and would
   not embed a plaintext password in the script.

4. **Comments on the three `CAST AS BIGINT` lines repeat.**
   `deletions_controller.rb:43`, `videos_controller.rb:11`, `list_videos.rb:27`
   each carry:
   `# CAST AS BIGINT is Postgres-portable. MySQL used SIGNED; replaced during Phase 2.`
   Per the project style (CLAUDE.md), comments earn their keep when they explain
   WHY. The current text states WHAT (true) and WHEN (low value). Either drop
   two of the three (keep one as a precedent for the reader) or rewrite as a
   single sentence pointing at `docs/architecture.md`.

5. **`config/application.rb:42-46` comment is fine** — it explains WHY the
   timezone pin exists (Groupdate predictability). Keep as-is.

6. **`db/migrate/20260501165846_change_saved_views_url_to_citext.rb` `down`
   method** uses `change_column ..., :string`, but the original column was
   `t.string :url, null: false` with a unique index `[:kind, :url]` (preserved
   through the change). The `down` will work because `null: false` is preserved,
   but if the index relied on case-insensitive comparison via citext, the
   rollback creates a case-sensitive index. Low-risk because the `up` only runs
   against fresh DBs in development; flag for awareness only — no action
   recommended.

7. **`docs/setup.md` step 5** uses `bin/rails db:prepare` which is the correct
   modern idiom. The pre-diff `bin/setup` ran a manual sequence; the docs are
   more concise now. Good.

8. **`db/schema.rb` includes `enable_extension "pg_catalog.plpgsql"`** — this is
   auto-added by Rails on every Postgres dump and is not in the migration. Not a
   problem; flag for awareness because the spec says "the three
   `enable_extension` lines" and there are now four.

9. **`.env.example` could group `POSTGRES_*` and `MYSQL_*` blocks more
   cleanly.** Current ordering interleaves them with separating comments. Minor.

10. **`saved_view_spec.rb` already uses `.case_insensitive`** in the shoulda
    matcher and would be a natural place to add a direct citext spec (see
    A.3.2). Not a simplification; a coverage addition.

---

## Phase C — Gate results

| Gate                                       | Result                                                                                                                                                                                                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `bundle exec rspec`                        | **423 examples, 0 failures.** Run from clean shell (`env -i HOME=$HOME PATH=$PATH bash -lc`); 16.62s wall. Some `:unprocessable_entity` deprecation warnings from `rspec-rails` — not introduced here. |
| `bundle exec brakeman --quiet`             | **Errors: 0, Security Warnings: 0.** Controllers: 9, Models: 12, Templates: 38.                                                                                                                        |
| `bundle exec bundler-audit check --update` | **No vulnerabilities found.** Advisory DB updated to 2026-03-30.                                                                                                                                       |
| Diff stat                                  | **29 files changed, 299 insertions(+), 83 deletions(-).** (24 modified + 5 new: extensions migration, citext migration, extensions spec, architecture doc, setup doc.)                                 |

---

## Verdict

**YELLOW** — ready for the manual playbook, but two items want attention before
commit:

1. **CI workflow update** (A.1.1, A.1.2). Without this, the next push to a
   feature branch will fail CI on `mysql2` not being in the bundle. Suggest the
   architect either (a) extend Phase 2's scope to include `ci.yml`, or (b)
   explicitly defer it to a follow-up branch with a `log.md` note. Picking (a)
   is small and tight: swap the service block, swap env vars, restore the
   `POSTGRES_*` env-var overrides in `database.yml`'s `test:` block.

2. **`bin/setup` plaintext password** (A.1.4). Cosmetic but worth fixing in the
   same pass.

Everything else (citext spec coverage, dated comment, comment duplication, A.4
doc inconsistencies, plan/log/dev-kb checkbox ticking) is post-merge or YELLOW
informational. Gates are green and the diff matches the spec end-to-end on the
substantive items. After CI is sorted (or explicitly deferred) and the playbook
runs green, the migration is ready to commit.
