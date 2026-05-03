# Security Audit — Phase 2 Postgres Migration

**Branch**: step-postgres **Auditor date**: 2026-05-01 **Diff stat**:

```
 .env.example                                       | 10 ++++++
 CLAUDE.md                                          |  6 ++--
 Gemfile                                            |  2 +-
 Gemfile.lock                                       |  9 +++--
 app/controllers/deletions_controller.rb            |  3 +-
 app/controllers/videos_controller.rb               |  3 +-
 app/mcp/tools/create_video.rb                      |  2 +-
 app/mcp/tools/list_videos.rb                       |  3 +-
 app/models/app_setting.rb                          |  2 +-
 app/models/channel.rb                              |  2 +-
 app/models/playlist.rb                             |  2 +-
 app/models/playlist_item.rb                        |  2 +-
 app/models/video.rb                                |  2 +-
 bin/dev                                            |  2 +-
 bin/setup                                          | 22 ++++++------
 config/application.rb                              |  6 ++++
 config/credentials.yml.enc                         |  2 +-
 config/database.yml                                | 36 +++++++++----------
 db/migrate/20260426150307_create_videos.rb         |  2 +-
 db/migrate/20260426222642_create_bulk_operations.rb|  6 ++--
 db/schema.rb                                       | 40 +++++++++++++---------
 docker-compose.yml                                 | 23 +++++++------
 docker/mysql/init.sql                              |  3 --
 spec/mcp/tools/create_video_spec.rb                |  2 +-
 24 files changed, 109 insertions(+), 83 deletions(-)
```

Plus untracked: `db/migrate/20260501165845_enable_postgres_extensions.rb`,
`db/migrate/20260501165846_change_saved_views_url_to_citext.rb`,
`spec/db/extensions_spec.rb`, `docs/architecture.md`, `docs/setup.md`.

## Verdict

**PASS with caveats** — Brakeman (`-w1`) reports zero warnings, bundler-audit
reports zero CVEs, Active Record Encryption columns are untouched, no plaintext
secrets are introduced, and the diff contains no exploitable code paths. Two
HIGH-severity items are local-dev hygiene issues (LAN-exposed Postgres with
`trust` auth, plaintext `Pass123#` in `bin/setup` help text); both predate this
branch in equivalent form (MySQL had `MYSQL_ALLOW_EMPTY_PASSWORD: yes` plus the
same exposed port and the same plaintext default), so neither is a net
regression. They MUST NOT carry into production (Phase 16) and should be
hardened in this phase or tracked as a follow-up.

## Findings by severity

### CRITICAL

- (none)

### HIGH

- **H-1. Postgres listens on `0.0.0.0:5433` with
  `POSTGRES_HOST_AUTH_METHOD: trust`** — `docker-compose.yml:5–10`. Verified at
  runtime: `ss -ltn` shows `0.0.0.0:5433` and `[::]:5433`. Combined with
  `trust`, any host on the LAN can connect as the `pito` superuser with no
  password and read/write the development database (which contains real OAuth
  tokens via `Channel#oauth_access_token` once seeded with live data). The prior
  MySQL config had the analogous problem (`MYSQL_ALLOW_EMPTY_PASSWORD: yes` +
  `0.0.0.0:3307`), so this is **not a regression vs. main**, but the spec
  explicitly asks to flag it. **Mitigation**: bind the host port to loopback by
  changing the port mapping to `"127.0.0.1:${POSTGRES_PORT:-5433}:5432"` (and
  same for `redis` and `meilisearch`). Apply in this branch — it is a
  one-character change with no downside for local dev. Also document in
  `decisions/` that production (Phase 16) MUST replace `trust` with password
  auth driven by credentials. **Assessment: true positive, not a regression.**

- **H-2. Plaintext database password `Pass123#` checked into `bin/setup`** —
  `bin/setup:50,54`. The bootstrap helper prints the literal credentials block
  including `password: "Pass123#"` to stdout when the user runs setup. The same
  string appears in the deleted `docker/mysql/init.sql` on `main` (which
  contained `IDENTIFIED BY 'Pass123#'`), so this is also **not a regression vs.
  main**, but it remains a defense-in-depth concern: the project's de-facto
  local password is in the public source tree and any developer who copy-pastes
  the help block ends up with that exact value in their encrypted credentials.
  **Mitigation**: replace the literal with a placeholder such as
  `password: "<choose-a-strong-password>"` and have the help text instruct the
  user to `openssl rand -base64 24`. **Assessment: true positive, not a
  regression.**

### MEDIUM

- **M-1. Legacy `:mysql` credentials block retained in
  `config/credentials.yml.enc` during the cutover window** — diff lines 297–310.
  The spec explicitly authorises this for rollback safety and mandates removal
  in the post-verification cleanup (section 4b). The risk is minor (encrypted at
  rest; same data already present on `main`), but two parallel credential blocks
  containing the same secret double the surface area and increase the chance the
  wrong one is referenced after Phase 16. **Mitigation**: tracked by spec
  section 4b; ensure the cleanup pass actually fires before any branch touching
  production credentials. **Assessment: true positive, time-boxed.**

- **M-2. Redis (6380) and Meilisearch (7700) also bind to `0.0.0.0`** —
  `docker-compose.yml:21,33`. Same root cause as H-1; called out separately
  because Redis is the Sidekiq queue and Rails cache, and Meilisearch holds a
  search index of titles/descriptions. Neither has authentication enabled in the
  compose file. Same loopback fix applies. **Assessment: true positive, not a
  regression.**

### LOW

- **L-1. `meilisearch` healthcheck issues an HTTP request to
  `http://127.0.0.1:7700/health` from inside the container** —
  `docker-compose.yml:41`. Functionally fine and an improvement over the prior
  `http://localhost:...`. Listed only to confirm the auditor noticed the change
  is benign. **Assessment: false positive (informational).**

- **L-2. `enable_extension` in the new migration runs as the database role** —
  `db/migrate/20260501165845_enable_postgres_extensions.rb`. The `pito` role
  inside the dev container is created as a superuser by the official Postgres
  entrypoint, so `CREATE EXTENSION` succeeds. In production (Phase 16) the app
  role will not be a superuser and this migration will fail unless run by a
  privileged migrator role. Not a security issue per se — call it a Phase 16
  deployment-runbook item. **Assessment: true positive, deferred.**

### INFO

- **I-1. `tags` column type changed from `t.json` to `t.jsonb`** —
  `db/migrate/20260426150307_create_videos.rb`, `db/schema.rb`. No security
  impact; `jsonb` is the standard Postgres choice and supports indexed queries.
  Validates via the existing model.

- **I-2. `case_sensitive: false` added to five `validates :*, uniqueness: …`
  calls** — `app/models/{app_setting,channel,playlist,playlist_item,video}.rb`.
  Required because Postgres string equality is case-sensitive while MySQL
  utf8mb4*unicode_ci was not. The check is enforced at the Rails layer; the
  underlying DB unique indexes (visible in `db/schema.rb`) remain case-sensitive
  on plain `string` columns. This widens the window between two Rails processes
  inserting near-simultaneous records that differ only in case (TOCTOU). For
  `youtube*\*\_id`columns the YouTube API guarantees a fixed canonical case so the practical risk is zero. For`app_settings.key`(used by`AppSetting.get/set`)
  the same guarantee holds — keys are constants set in code. **Assessment: not a
  finding, called out for the record.**

- **I-3. `saved_views.url` migrated to `citext`** —
  `db/migrate/20260501165846_change_saved_views_url_to_citext.rb`. Eliminates
  the I-2-style TOCTOU for that column at the database layer. Good
  defense-in-depth.

- **I-4. `app/mcp/tools/create_video.rb` now splits `tags` from a comma-string
  into an array** — diff line 132. Pure data-shaping change driven by the
  `t.jsonb :tags` migration. The new path applies
  `to_s.split(",").map(&:strip).reject(&:blank?)` to a tool-supplied string; no
  SQL is constructed from this value. The MCP tool surface is unchanged (input
  schema still declares
  `tags: { type: "string", description: "Comma-separated tags" }`). MCP token
  enforcement (Phase 3+) is not weakened — the change is inside the tool body,
  downstream of any auth wrapper. **Assessment: not a finding.**

- **I-5. Three new SQL fragments cast
  `SUM(video_stats.watch_time_minutes) AS BIGINT`** —
  `app/controllers/{deletions,videos}_controller.rb`,
  `app/mcp/tools/list_videos.rb`. Static literal strings with no interpolation.
  No SQL injection vector. **Assessment: not a finding.**

- **I-6. `network_mode: host` is not present in `docker-compose.yml`** —
  verified by `grep -n network_mode`. The implementer's deviation note (iptables
  workaround, then reverted) is honoured.

- **I-7. `config/credentials.yml.enc` is base64 ciphertext** — verified via
  `file` and `od -c`. The diff hash change reflects the encrypted blob, not
  plaintext exposure.

- **I-8. `config/master.key` is gitignored and not in the diff** — confirmed by
  `git ls-files` and the project `.gitignore`.

- **I-9. CSRF posture unchanged** — no new POST/PUT/DELETE endpoints; controller
  files modified only adjusted SQL fragments. MCP tool transport (CSRF-exempt by
  design) is unchanged.

## Brakeman output (full)

```
== Brakeman Report ==

Application Path: ~/Dev/pito-project/pito
Rails Version: 8.1.3
Brakeman Version: 8.0.4
Scan Date: 2026-05-01 18:49:30 +0200
Duration: 0.656035917 seconds
Checks Run: BasicAuth, BasicAuthTimingAttack, CSRFTokenForgeryCVE, ContentTag,
CookieSerialization, CreateWith, CrossSiteScripting, DefaultRoutes, Deserialize,
DetailedExceptions, DigestDoS, DynamicFinders, EOLRails, EOLRuby, EscapeFunction,
Evaluation, Execute, FileAccess, FileDisclosure, FilterSkipping, ForgerySetting,
HeaderDoS, I18nXSS, JRubyXML, JSONEncoding, JSONEntityEscape, JSONParsing, LinkTo,
LinkToHref, MailTo, MassAssignment, MimeTypeDoS, ModelAttrAccessible,
ModelAttributes, ModelSerialize, NestedAttributes, NestedAttributesBypass,
NumberToCurrency, PageCachingCVE, Pathname, PermitAttributes, QuoteTableName,
Ransack, Redirect, RegexDoS, Render, RenderDoS, RenderInline, RenderRCE,
ResponseSplitting, RouteDoS, SQL, SQLCVEs, SSLVerify, SafeBufferManipulation,
SanitizeConfigCve, SanitizeMethods, SelectTag, SelectVulnerability, Send, SendFile,
SessionManipulation, SessionSettings, SimpleFormat, SingleQuotes, SkipBeforeFilter,
SprocketsPathTraversal, StripTags, SymbolDoSCVE, TemplateInjection, TranslateBug,
UnsafeReflection, UnsafeReflectionMethods, ValidationRegex, VerbConfusion,
WeakRSAKey, WithoutProtection, XMLDoS, YAMLParsing

== Overview ==

Controllers: 9
Models: 12
Templates: 38
Errors: 0
Security Warnings: 0

== Warning Types ==

No warnings found
```

## bundler-audit output

```
Updating ruby-advisory-db ...
From https://github.com/rubysec/ruby-advisory-db
 * branch            master     -> FETCH_HEAD
Already up to date.
Updated ruby-advisory-db
ruby-advisory-db:
  advisories:	1078 advisories
  last updated:	2026-03-30 08:43:42 -0700
  commit:	b1e3c15af5cc5c1058c6db9a876a082685f4a3f8
No vulnerabilities found
```

## Secrets-grep output

```
$ git diff main...step-postgres | grep -iE '(password|secret|token|key) *[:=] *["\x27][^"\x27]*["\x27]'

     password: "Pass123#"            (config/credentials.yml.enc — encrypted blob, value visible only because the diff happens to render the contextual line; not plaintext on disk)
+    password: "Pass123#"            (config/credentials.yml.enc — same; postgres block added)
+    password: "Pass123#"            (config/credentials.yml.enc — same; postgres test block)
-      MYSQL_ALLOW_EMPTY_PASSWORD: "yes"   (docker-compose.yml — removed; replaced with POSTGRES_HOST_AUTH_METHOD: trust)
```

Additional secrets-grep on the working tree (not the diff):

- `bin/setup:50,54` — `password: "Pass123#"` in plaintext help text. **See
  H-2.**
- `.env.example`, `.env.development`, `.env.test` — no secrets. Only
  `MYSQL_HOST/PORT`, `POSTGRES_HOST/PORT`, `REDIS_URL`, `MEILISEARCH_URL`,
  `MAX_PANES`, `PANE_TITLE_LENGTH`. Confirmed clean.
- `docker-compose.yml` — `POSTGRES_USER: pito`, `POSTGRES_DB: pito_development`,
  `POSTGRES_HOST_AUTH_METHOD: trust`. No password literal (the prior MySQL block
  had `MYSQL_ALLOW_EMPTY_PASSWORD: yes`, also no password literal). `trust` is
  acceptable for local dev only — **see H-1**.
- `config/database.yml` — only `Rails.application.credentials.dig(:postgres, …)`
  reads, with empty-string fallbacks. No literal credentials. The production
  block correctly omits the fallback so a missing credential fails loudly.

## Must-not-regress items for later phases

1. **Phase 16 (production hardening) MUST replace
   `POSTGRES_HOST_AUTH_METHOD: trust`** with password-based auth
   (`scram-sha-256`) sourced from credentials. The `pito` role MUST be reduced
   from superuser to a least-privilege role with `CREATEDB` and standard CRUD on
   the application schema only. A separate migrator role with `CREATE EXTENSION`
   privileges runs the extension-enable migration once during deploy.
2. **Phase 16 MUST NOT publish Postgres (or Redis or Meilisearch) on a public
   interface.** All three are exposed via Docker port mappings; in production
   they should be on an internal Docker network with no host port mapping at
   all.
3. **Phase 2 cleanup pass (spec section 4b) MUST remove the legacy `:mysql`
   credentials block, the `MYSQL_HOST` / `MYSQL_PORT` keys from `.env.example`
   and `.env.{development,test}`, and the deleted `docker/mysql/` directory
   references from any documentation.** Track in the phase log so it is not
   silently dropped.
4. **The plaintext `Pass123#` in `bin/setup` help text MUST be replaced with a
   placeholder before the project is shared, open-sourced, or any new
   contributor is onboarded.** Even though it is only a hint, it is the de-facto
   default and shows up verbatim in encrypted credentials in every developer's
   checkout.
5. **Active Record Encryption columns (`AppSetting#value`,
   `Channel#oauth_access_token`, `Channel#oauth_refresh_token`) MUST round-trip
   cleanly post-migration.** The spec mandates this; the existing model specs
   cover encrypt/decrypt behaviour and run as part of the suite. No code change
   in this diff alters the encryption configuration.

## Recommended actions before commit

1. **(HIGH, fix in this branch)** Bind all three Docker host ports to loopback:
   change `"${POSTGRES_PORT:-5433}:5432"` →
   `"127.0.0.1:${POSTGRES_PORT:-5433}:5432"` in `docker-compose.yml`, and the
   equivalent for `redis` and `meilisearch`. Verify with `ss -ltn` that the
   listen address becomes `127.0.0.1:5433` rather than `0.0.0.0:5433`. Resolves
   H-1, M-2.
2. **(HIGH, fix in this branch)** Replace the `Pass123#` literal in
   `bin/setup:50,54` with a placeholder and an `openssl rand -base64 24`
   instruction. Resolves H-2.
3. **(MEDIUM, follow-up)** Add an ADR under `pito-dev-kb/decisions/` recording:
   (a) `trust` mode is local-dev-only; (b) the production hardening checklist
   for Phase 16; (c) the loopback-binding rule for all dev compose services
   going forward. This prevents the rationale from being lost between phases.
4. **(LOW, follow-up)** During the spec-section-4b cleanup pass, also delete the
   `MYSQL_*` lines from `bin/setup` if any remain, the `:mysql` credentials
   block from both shared and per-environment encrypted credentials files, and
   any references from `docs/setup.md` and `docs/architecture.md`.
5. **(INFO)** Confirm the existing `AppSetting`, `Channel` model specs run green
   against Postgres before the user merges — they exercise the Active Record
   Encryption round-trip implicitly. The new `spec/db/extensions_spec.rb`
   confirms `pgcrypto`, `citext`, and `vector` are loaded.
