# Security Audit — Channel Revamp

**Date**: 2026-05-02 **Branch**: main (Wave 2b changes are in the working tree,
not yet committed; baseline = 9f0fd39) **Diff stat** (working tree vs. 9f0fd39,
Gemfile.lock excluded):

```
 Gemfile                                            |   3 +
 app/assets/tailwind/application.css                |   6 +
 app/controllers/channels_controller.rb             |  92 ++++--
 app/controllers/dashboard_controller.rb            |  10 +-
 app/controllers/deletions_controller.rb            |  41 +--
 app/controllers/search_controller.rb               |   3 -
 app/decorators/channel_decorator.rb                |  30 +-
 app/decorators/video_decorator.rb                  |   2 +-
 app/helpers/application_helper.rb                  |  12 +-
 app/javascript/controllers/bulk_select_controller.js          |  26 +-
 app/javascript/controllers/operation_progress_controller.js   |   2 +
 app/mcp/tools/create_channel.rb                    |  35 ++-
 app/mcp/tools/delete_records.rb                    |  15 +-
 app/mcp/tools/get_channel.rb                       |   2 +-
 app/mcp/tools/get_dashboard.rb                     |   4 +-
 app/mcp/tools/list_channels.rb                     |  29 +-
 app/mcp/tools/search_content.rb                    |   8 +-
 app/mcp/tools/update_channel.rb                    |  30 +-
 app/models/bulk_operation.rb                       |   2 +-
 app/models/bulk_operation_item.rb                  |   2 +-
 app/models/channel.rb                              |  38 ++-
 app/models/saved_view.rb                           |  11 +-
 app/views/bulk_operations/_item_row.html.erb       |   2 +
 app/views/bulk_operations/show.html.erb            |   2 +
 app/views/channels/_add_pane_dialog.html.erb       |  12 +-
 app/views/channels/_form.html.erb                  |  36 ++-
 app/views/channels/_pane.html.erb                  |  26 +-
 app/views/channels/_picker.html.erb                |  35 ++-
 app/views/channels/edit.html.erb                   |   7 +-
 app/views/channels/new.html.erb                    |   2 +-
 app/views/channels/panes.html.erb                  |  18 +-
 app/views/channels/show.html.erb                   |  34 ++-
 app/views/dashboard/index.html.erb                 |  60 +++-
 app/views/deletions/progress.html.erb              |  16 +-
 app/views/deletions/show.html.erb                  |  16 +-
 app/views/search/show.html.erb                     |  35 +--
 app/views/videos/_add_pane_dialog.html.erb         |   2 +-
 app/views/videos/_form.html.erb                    |   3 +-
 app/views/videos/_pane.html.erb                    |   2 +-
 app/views/videos/index.html.erb                    |   2 +-
 config/routes.rb                                   |   4 +-
 config/sidekiq_cron.yml                            |   5 +
 db/schema.rb                                       |  44 ++-
 db/seeds.rb                                        | 234 ++++++++-------
 (specs trimmed)
 68 files changed, 1173 insertions(+), 767 deletions(-)
```

New files (untracked): `app/controllers/concerns/confirmable.rb`,
`app/controllers/syncs_controller.rb`,
`app/javascript/controllers/dashboard_chart_visibility_controller.js`,
`app/jobs/bulk_sync_job.rb`, `app/jobs/channel_sync.rb`,
`app/jobs/sync_starred_channels_job.rb`,
`app/mcp/tools/bulk_delete_channels.rb`, `app/mcp/tools/bulk_sync_channels.rb`,
`app/models/current.rb`, `app/models/tenant.rb`, `app/models/user.rb`,
`app/views/syncs/show.html.erb`, `app/views/syncs/progress.html.erb`, three new
migrations (`20260501220624_create_tenants.rb`,
`20260501220625_create_users.rb`, `20260501220626_revamp_channels.rb`), plus
their specs.

## Verdict

**PASS** — Brakeman `-w1` reports 0 warnings; bundler-audit reports 0 CVEs; the
new `SyncsController`, `BulkSyncJob`,
`bulk_sync_channels`/`bulk_delete_channels` MCP tools, and the new
`User`/`Tenant`/`Current` primitives introduce no exploitable code paths. URL
validation is strict and tied to a single regex constant. Strong params on
`ChannelsController#update` correctly forbid `channel_url`. The MCP confirm flag
is honored explicitly. localStorage values are server-controlled slug strings.
Container ports remain bound to 127.0.0.1 from Phase 2 cleanup. No plaintext
secrets land in env/docker/setup. Two LOW items and a small set of
INFO/forward-looking observations are listed below; none gate the merge.

## Findings by severity

### CRITICAL

- (none)

### HIGH

- (none)

### MEDIUM

- (none)

### LOW

- **L-1. `delete_records` MCP tool still has a Channel branch that bypasses the
  confirm/preview flow.** `app/mcp/tools/delete_records.rb:26-37` still
  dispatches `type == "channel"` straight to
  `Channel.where(id: ids).destroy_all` with no confirm parameter. The spec at
  `pito-dev-kb/plans/beta/03-channel-revamp/specs/channel-revamp.md:135` calls
  for dropping the channel branch from `delete_records` so all channel deletion
  flows through `bulk_delete_channels` (which enforces the two-step
  preview/confirm). This is not exploitable on its own (the MCP client is a
  trusted local agent today and there is no network auth surface yet), but it
  defeats the bulk-confirm safety rail when an LLM-driven client picks the
  legacy path. The tool description was updated to **prefer**
  `bulk_delete_channels` but the channel branch remains live as a fallback.
  **Recommendation**: drop the `when "channel"` branch in `delete_records` and
  let it fall through to `unknown type` for channels.

- **L-2. `update_channel` MCP tool: extras-key check uses
  `**extras`but the input_schema permits only`id`, `star`, `connected`.** `app/mcp/tools/update_channel.rb:19-24`defends against`channel_url`arriving via`additionalProperties`by inspecting`extras`, which is correct defense-in-depth. However the JSON schema does not set `additionalProperties:
  false`, so other arbitrary keys silently pass through to `extras`and are dropped without error. Not a security issue (the model also enforces`prevent_url_change`, and only `:star`/`:connected`are mass-assigned via the`attrs`hash), but the schema would be tighter with`additionalProperties:
  false`. **Recommendation (defense-in-depth, not blocking)**: add `additional_properties:
  false` to the schema.

### INFO

- **I-1. `ApplicationController` does not yet set
  `Current.tenant`/`Current.user`.** `app/controllers/application_controller.rb`
  has no `before_action :set_current_tenant_and_user`. The spec calls for it
  (single-tenant shim during Phase B). The `Current` model exists; the wiring is
  missing. Behavior today: `Current.tenant` is `nil` for web requests, and
  `CreateChannel` MCP tool falls back to `Tenant.first&.id`. Not a security
  issue this phase, but **must be wired before any auth/session work lands**,
  otherwise tenant scoping cannot be relied upon by future code.

- **I-2. `Tenant.find_or_initialize_by` race in
  `ChannelsController#default_tenant`.**
  `app/controllers/channels_controller.rb:131-135` does
  `Tenant.order(:id).first || Tenant.create!(name: "Primary")`. Under concurrent
  first-time requests this could race and create two `Primary` rows (no
  uniqueness on `tenants.name`). Not exploitable, just flaky. Goes away once
  `set_current_tenant_and_user` is wired.

- **I-3. `User` model does NOT include `password_digest` in any JSON output.**
  Verified: there is no `as_json`/`to_json` override exposing it, no controller
  renders a `User`, no MCP tool serializes a `User`, no decorator exists for
  `User`. `has_secure_password` keeps `password_digest` as a column attribute
  but Rails' default `as_json` would include it if a User were ever rendered.
  Today this is moot (User is seed-only and never serialized). **Forward-looking
  item**: when authentication is added (Phase 7+), make sure any User
  serialization explicitly excludes `password_digest`.

- **I-4. `app/views/search/show.html.erb:33` calls `html_safe` on Meilisearch
  highlights.** Pre-existing code, untouched by this revamp (the diff only
  **removed** the channel-search section from this view). Meilisearch highlights
  are derived from indexed `Video.title` / `Video.description` and the engine
  returns HTML-wrapped highlight markers. The `html_safe` here is the canonical
  Meilisearch + Rails pattern. With Channel removed from the searchable list
  this audit, the only data source feeding `html_safe` is `Video` rows the user
  themselves created or seeded. No regression in this phase. Worth a future
  hardening pass to render the highlights via a sanitized helper.

- **I-5. Channel `[ view ]` link templates the user-supplied `channel_url`
  directly into `href`.** `app/views/channels/_pane.html.erb:8` and
  `app/views/channels/_picker.html.erb:65` use
  `<a href="<%= channel.channel_url %>" target="_blank" rel="noopener noreferrer" class="bracketed">[ view ]</a>`.
  ERB escaping handles the attribute correctly, AND the strict regex
  `\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z` (defined as
  `Channel::CHANNEL_URL_REGEX`, enforced at the model layer in both create and
  update via `validates :channel_url, format:` and `prevent_url_change`,
  mirrored by `CreateChannel` MCP tool) makes a `javascript:` or other-scheme
  URL impossible to persist. The HTML form input also carries the same `pattern`
  regex (`app/views/channels/_form.html.erb:11`) for client-side hint, but the
  model regex is the source of truth. Both `target="_blank"` links carry
  `rel="noopener noreferrer"` — reverse-tabnabbing prevention is in place. **No
  issue; documented as INFO so future reviewers don't re-flag it.**

- **I-6. `BulkSyncJob` uses `op_item.target` polymorphic dereference.**
  `app/jobs/bulk_sync_job.rb:27-44` reads `op_item.target` and conditionally
  calls `ChannelSync.perform_async(target.id) if target.is_a?(Channel)`.
  Mid-flight deletion is handled (`if target.nil?` branch records `:failed`).
  The `is_a?(Channel)` check defends against a future world where `bulk_sync`
  items target other classes. No fail-fast — error in one item does not abort
  the rest. Behaves as the spec dictates.

- **I-7. `ChannelSync` placeholder is a no-op.** `app/jobs/channel_sync.rb`
  flips `syncing: true`, performs no work, then in the `ensure` block flips it
  back and stamps `last_synced_at`. Phase B placeholder; the real network work
  lands in a later phase. No security concern today; flag for the YouTube-API
  security review when that lands (URL fetch / SSRF / credential leak).

- **I-8. `SyncStarredChannelsJob` iteration is bounded.**
  `app/jobs/sync_starred_channels_job.rb:8` uses
  `Channel.where(star: true).find_each`. With 7 starred channels seeded, this
  enqueues 7 `ChannelSync` jobs/day at midnight. Not unbounded (the spec called
  for `Channel.all.each` to be flagged; this code uses a properly filtered
  `where(star: true)` which is correct). No DoS risk.

- **I-9. `dashboard_chart_visibility_controller.js` localStorage values are
  server-controlled.** Slugs come from `data-chart-id="daily-views"` /
  `views-by-channel"` / `top-videos"` / `daily-engagement"` set by
  `app/views/dashboard/index.html.erb`, all hard-coded. The controller never
  reads slugs from user input; the `toggle()` action reads
  `event.target.dataset.chartTarget` which is also server-controlled.
  localStorage value `pito_dashboard_charts_visible` stores a JSON array of
  these slug strings. No injection vector. Note: there is a minor bug —
  `_writeStorage(this._currentVisibleIds())` is called from `toggle()` after the
  fact, but `toggle()` does not re-add a slug when the checkbox is checked back
  on (it relies on `_currentVisibleIds` recomputing from current checkbox
  state). That is functional, not security-relevant.

- **I-10. Sidekiq Web mount uses constant-time string comparison.**
  `config/routes.rb:5-12` is unchanged this phase but worth confirming it still
  uses `ActiveSupport::SecurityUtils.secure_compare` (yes). Pre-existing; no
  regression.

- **I-11. CSRF protection is in place by default.** Rails 8 +
  `ActionController::Base` enables `protect_from_forgery with: :exception`
  automatically. No `skip_before_action :verify_authenticity_token` and no
  `skip_forgery_protection` anywhere in the diff. The new `SyncsController` does
  not opt out. The MCP HTTP transport at `/mcp` is mounted as a standalone Rack
  app (not subclassing `ActionController::Base`), so it does not participate in
  Rails' CSRF middleware — that is by design (MCP is JSON-RPC over a separate
  Puma at port 3001) and is the same pattern as Phase 2. INFO so the next
  reviewer knows the answer without re-deriving it.

- **I-12. URL-validation parity between layers.** Model:
  `Channel::CHANNEL_URL_REGEX = %r{\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z}`.
  `CreateChannel` MCP tool reuses the same constant
  (`app/mcp/tools/create_channel.rb:24` calls
  `url.match?(Channel::CHANNEL_URL_REGEX)`). HTML form uses the equivalent
  `pattern=` regex. No drift.

- **I-13. `Confirmable#load_items` redirects on unknown `:type` and on empty
  `ids`.** `app/controllers/concerns/confirmable.rb:23,30` correctly redirects
  to `root_path` / `cancel_path` with a flash. The whitelist
  `TYPES = %w[channel video].freeze` is the only allowed input. No SQL injection
  vector through `:type`. The `:ids` param is split on `,` and each token is
  passed to `where(id: ids)`, which Rails parameterizes.
  `Channel.where(id: ids).order(channel_url: :asc)` — no string interpolation.

- **I-14. `ChannelsController#sort_clause` uses an allowlist for both column and
  direction.** `app/controllers/channels_controller.rb:137-141` resolves
  `params[:sort]` against a fixed `ALLOWED_SORTS` hash and `params[:dir]`
  against `%w[asc desc]`, then constructs `Arel.sql("#{column} #{direction}")`.
  Since both halves are validated against allowlists, the `Arel.sql` is safe.
  INFO so it doesn't get flagged on re-audit.

- **I-15. `RevampChannels` migration uses raw SQL with `connection.quote` and
  integer coercion.**
  `db/migrate/20260501220626_revamp_channels.rb:104-110,90-93` builds
  `UPDATE channels SET tenant_id = #{seeded_tenant_id.to_i}, channel_url = #{connection.quote(url)}`
  — both branches are properly sanitized (one is `.to_i`, one is
  `connection.quote`). No SQL-injection risk; this is a one-shot migration
  anyway.

- **I-16. MCP confirm-flag bypass: verified absent.** `bulk_delete_channels` and
  `bulk_sync_channels` both gate their state-changing branch behind
  `if confirm == true` (strict `==`, not `if confirm`). A `confirm: false` or
  absent `confirm` returns the preview-only path with no `BulkOperation` row
  created and no job enqueued. Verified by reading the call paths in
  `app/mcp/tools/bulk_delete_channels.rb:48` and
  `app/mcp/tools/bulk_sync_channels.rb:57`.

- **I-17. localStorage Stimulus controller has a private-mode try/catch.**
  `dashboard_chart_visibility_controller.js:60-77` swallows `localStorage`
  exceptions silently. Acceptable.

- **I-18. Open-redirect surface on `cancel_path`.** `Confirmable#cancel_path`
  returns one of three path-helper-resolved values (`channels_path`,
  `videos_path`, `root_path`). No user input interpolated. The form's cancel
  link in `_action_screen.html.erb` and
  `syncs/show.html.erb`/`progress.html.erb` consume `@cancel_path` from this
  allowlist. No open-redirect vector.

- **I-19. Job DoS: bounded.** `SyncStarredChannelsJob` is bounded by the
  starred-channel set (7 today). `BulkSyncJob` iterates only the per-operation
  `bulk_operation_items` set the controller built. `BulkSyncJob` and
  `ChannelSync` both call `find_by` and tolerate nil. `ChannelSync` retry: 3 —
  fine.

## Brakeman output (-w1)

```
== Brakeman Report ==

Application Path: ~/Dev/pito-project/pito
Rails Version: 8.1.3
Brakeman Version: 8.0.4
Scan Date: 2026-05-02 00:50:26 +0200
Duration: 1.036399136 seconds
Checks Run: BasicAuth, BasicAuthTimingAttack, CSRFTokenForgeryCVE, ContentTag,
            CookieSerialization, CreateWith, CrossSiteScripting, DefaultRoutes,
            Deserialize, DetailedExceptions, DigestDoS, DynamicFinders, EOLRails,
            EOLRuby, EscapeFunction, Evaluation, Execute, FileAccess, FileDisclosure,
            FilterSkipping, ForgerySetting, HeaderDoS, I18nXSS, JRubyXML, JSONEncoding,
            JSONEntityEscape, JSONParsing, LinkTo, LinkToHref, MailTo, MassAssignment,
            MimeTypeDoS, ModelAttrAccessible, ModelAttributes, ModelSerialize,
            NestedAttributes, NestedAttributesBypass, NumberToCurrency, PageCachingCVE,
            Pathname, PermitAttributes, QuoteTableName, Ransack, Redirect, RegexDoS,
            Render, RenderDoS, RenderInline, RenderRCE, ResponseSplitting, RouteDoS,
            SQL, SQLCVEs, SSLVerify, SafeBufferManipulation, SanitizeConfigCve,
            SanitizeMethods, SelectTag, SelectVulnerability, Send, SendFile,
            SessionManipulation, SessionSettings, SimpleFormat, SingleQuotes,
            SkipBeforeFilter, SprocketsPathTraversal, StripTags, SymbolDoSCVE,
            TemplateInjection, TranslateBug, UnsafeReflection, UnsafeReflectionMethods,
            ValidationRegex, VerbConfusion, WeakRSAKey, WithoutProtection, XMLDoS,
            YAMLParsing

== Overview ==

Controllers: 10
Models: 15
Templates: 40
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
git diff 9f0fd39 -- . ':(exclude)Gemfile.lock' \
  | grep -iE '(password|secret|token|key) *[:=] *["'][^"']*["']'

# Sole match (a SPEC FILE removal — Alpha-era oauth_access_token fixture being deleted):
-      channel = create(:channel, oauth_access_token: "***", oauth_refresh_token: "***")
```

The match above is a **deletion** in `spec/jobs/search_index_job_spec.rb` —
Alpha-era OAuth token columns being purged from a test factory call as part of
the channel revamp. No new plaintext secrets are added in the diff.

```
grep -E "password|secret" .env.development .env.test .env.example docker-compose.yml

# Only matches:
.env.example:# Postgres connection metadata only — secrets (database name,
.env.example:# username, password) live in Rails encrypted credentials under the

grep -E "password" db/seeds.rb
# Only matches (read from credentials, fall back to placeholder + warning):
  puts "           tenant_name, username, email, password."
owner_password = owner_creds&.dig(:password) || "change-me"
owner.password = owner_password
owner.password_confirmation = owner_password
```

Verified:

- No password in `.env.development` / `.env.test` / `.env.example` (only
  documentary comments in `.env.example`).
- No password in `docker-compose.yml` (Postgres uses
  `POSTGRES_HOST_AUTH_METHOD: trust` for local-only loopback dev — Phase 2
  stance, pre-existing, not a regression).
- No password in `bin/setup` help text (only the `<your-password>` placeholder
  string telling the user to put their own value into encrypted credentials).
- The owner block lives in `config/credentials.yml.enc` (encrypted, present on
  disk). `db/seeds.rb` reads `Rails.application.credentials.dig(:owner)` and
  falls back to `"change-me"` + a warning when missing — exactly as the spec
  mandates.
- `ss -ltn | grep -E '5433|6380|7700'` confirms loopback bindings:
  `127.0.0.1:5433`, `127.0.0.1:7700`, `127.0.0.1:6380`. Phase 2 hardening
  preserved.

## Must-not-regress items for later phases

- The strict `Channel::CHANNEL_URL_REGEX` constant must remain the single source
  of truth, used by both the model validator and the `CreateChannel` MCP tool.
  If the regex is loosened later (e.g., to support `/@handle` URLs), audit every
  place that interpolates `channel_url` into HTML/href contexts — currently safe
  only because the regex pins the scheme + host + path shape.
- `ChannelsController#update` strong params must keep `[:star, :connected]` (no
  `:channel_url`). The model-level `prevent_url_change` is the second line of
  defense; do not remove it on the assumption that strong params alone are
  enough.
- `bulk_delete_channels` and `bulk_sync_channels` must keep the strict
  `confirm == true` gate (not truthy `if confirm`). Boolean coercion via
  `confirm: true.to_s == "true"` would be a regression.
- `Confirmable::TYPES` whitelist (`%w[channel video]`) must stay an allowlist;
  never replace with a `to_sym.constantize` dispatch.
- The MCP HTTP transport remains its own Rack app — do not move MCP under
  `ActionController::Base` without a CSRF strategy compatible with non-browser
  MCP clients.
- When auth lands (Phase 7+), any User serializer must explicitly exclude
  `password_digest`. The User model carries it but no current code path
  serializes a User; that boundary must be defended once authn surfaces appear.
- `Sidekiq::Web` HTTP basic auth must keep
  `ActiveSupport::SecurityUtils.secure_compare`.
- Container ports must keep their `127.0.0.1:` prefix in `docker-compose.yml`
  until prod-grade auth lands.
- `delete_records` MCP channel branch (see L-1) should be dropped before the
  auth phase, otherwise an LLM-driven client could pick the legacy path.

## Recommended actions before/after merge

- **Before merge (LOW, optional)**: drop the channel branch from
  `app/mcp/tools/delete_records.rb` so all bulk channel deletion flows through
  `bulk_delete_channels` (matches the spec at line 135 of `channel-revamp.md`).
  One-line change.
- **Before merge (LOW, optional)**: add `additional_properties: false` to the
  `update_channel` MCP tool's input_schema for tighter contract.
- **Before merge or in the next session (INFO, required by spec)**: wire the
  `before_action :set_current_tenant_and_user` in `ApplicationController` (sets
  `Current.tenant = Tenant.first; Current.user = User.first`). The spec calls
  for it; today it is the only spec deviation visible from the controller layer.
- **After merge (forward-looking)**: when a `User` JSON serializer is introduced
  in a later phase, audit it explicitly for `password_digest` exposure. When
  `ChannelSync` gains real network I/O (Phase 7), security-review the YouTube
  API service layer for SSRF, OAuth token handling, and rate-limit DoS.
