# Phase 7 — Google OAuth + YouTube API Foundation · Session Log

## 2026-05-07 — Step 7A + 7B + 7C — Google OAuth, YouTube Client, Settings UI

**State at start:** Phases 6A (sessions / login) and 6B (Doorkeeper) had just
landed. `Sessions::AuthConcern` resolves `Current.user` / `Current.tenant` from
a cookie session; `Api::AuthConcern` (Phase 5) is the bearer-token surface and
stays untouched. YouTube gems (`google-apis-youtube_v3`,
`google-apis-youtube_analytics_v2`) were already in the bundle from Alpha;
OmniAuth was not. The `Rails.application.credentials.google_oauth` block had
`:client_id`, `:client_secret`, and `:project_id` populated; the user had
configured the Google Cloud Console with redirect URI
`https://app.pitomd.com/auth/google/callback`, scopes `youtube.readonly` +
`yt-analytics.readonly`, OAuth consent screen in testing mode. The user had NOT
yet exercised the OAuth flow with their real Google account, so VCR cassettes
against live traffic could not be recorded.

**Inputs:**

- `docs/plans/beta/07-google-oauth-youtube-foundation/specs/7a-google-oauth-and-identity.md`
- `docs/plans/beta/07-google-oauth-youtube-foundation/specs/7b-youtube-client-and-audit.md`
- `docs/plans/beta/07-google-oauth-youtube-foundation/specs/7c-settings-youtube-ui.md`
- Dispatch instruction (decision 7.16): use **WebMock stubs against canned
  response shapes** for the spec suite; VCR cassettes against the user's real
  account replace them in a follow-up cassette-recording session
  post-Phase-7-implementation.

**What landed (file-level):**

Phase 7A — Google OAuth + Identity:

- `Gemfile` / `Gemfile.lock` — added `omniauth-google-oauth2 (1.2.2)`,
  `omniauth-rails_csrf_protection (2.0.1)`. bundler-audit clean.
- `db/migrate/20260507300000_create_google_identities.rb` — table per spec
  §"Schema": tenant + user FKs, `google_subject_id` (unique within tenant),
  `email` (citext), encrypted `access_token` / `refresh_token` (text columns;
  ARE writes ciphertext), `expires_at`, `scopes` (jsonb), `needs_reauth`,
  `last_refreshed_at`, `last_authorized_at`, plus the partial index
  `(tenant_id, needs_reauth) WHERE needs_reauth = true`.
- `app/models/google_identity.rb` — `BelongsToTenant`, `belongs_to :user`,
  `has_many :channels` (nullify on destroy), `has_many :youtube_api_calls`
  (nullify), `encrypts :access_token`, `encrypts :refresh_token`, helpers
  (`access_token_expired?`, `needs_reauth?`, `has_scope?`, `scope_string`),
  Array validation on `scopes`.
- `config/initializers/omniauth.rb` — register `:google_oauth2` provider;
  default scope set is the userinfo trio (sign-in flow);
  `access_type: "offline"`, `prompt: "consent"`, `pkce: true`,
  `callback_path: "/auth/google/callback"` to match the URI registered with the
  Google Cloud Console; `redirect_uri` pinned in dev/production, nil in test
  (lets OmniAuth derive from request host).
- `config/routes.rb` — `match "/auth/google/callback" via [get post]` →
  `Auth::GoogleCallbacksController#create`; `/auth/failure` → `#failure`;
  dev-only `/auth/google` redirect to `/auth/google_oauth2`.
- `app/controllers/concerns/google_oauth_redirect.rb` — intent stash / consume
  helpers (`session[:google_oauth_intent]` carries `"youtube_connect"` between
  Settings → YouTube and the callback; `nil` for the sign-in branch).
- `app/controllers/auth/google_callbacks_controller.rb` — callback controller:
  read `request.env["omniauth.auth"]`, dispatch by intent, upsert identity,
  union scopes, reset `needs_reauth: false`. Sign-in branch leaves a
  `TODO(phase-12):` marker and redirects to `root_path`. `failure` action is
  `allow_anonymous`; `create` is NOT (the connect flow expects `Current.user` to
  be the signed-in Pito user — Phase 12 will graduate the sign-in branch when it
  lights up the login UI's Google button).
- `spec/support/google_stubs.rb` — WebMock stubs documenting the response shapes
  for the OAuth token / refresh / revoke endpoints with sensitive-data filter
  notes for the future cassette session.
- `spec/factories/google_identities.rb` + traits (`:expired`, `:needs_reauth`,
  `:no_refresh_token`).
- `spec/models/google_identity_spec.rb` — encryption-at-rest assertions (raw
  column read does not contain plaintext), helper coverage, cross-tenant
  scoping.
- `spec/requests/auth/google_callbacks_spec.rb` — drives OmniAuth's `test_mode`
  round-trip end-to-end (request phase → mocked auth_hash → callback). 10
  examples covering create / update / scope union / needs_reauth reset / sign-in
  placeholder / TODO marker presence / failure handler.
- `spec/system/google_oauth_flow_spec.rb` — system-level happy path: visit
  /settings/youtube → click [ connect google account ] → identity created →
  redirect lands.

Phase 7B — YouTube Client + Audit:

- `db/migrate/20260507300001_create_youtube_api_calls.rb` — append-only audit
  table per spec §"`youtube_api_calls`": tenant / user / google_identity FKs,
  `client_kind` ("oauth"|"public"), `endpoint`, `http_method`, `units`,
  `outcome`, `http_status`, `error_message`, `duration_ms`. Three composite
  indexes for daily-budget / kind-split / failure-trend lookups.
- `db/migrate/20260507300002_add_youtube_metadata_to_channels.rb` — additive:
  `title`, `description`, `subscriber_count`, `video_count`, `view_count`,
  `thumbnail_url`, `etag`, `synced_at`. No destructive change to existing
  placeholder columns.
- `db/migrate/20260507300003_add_youtube_metadata_to_videos.rb` — additive only:
  `view_count`, `like_count`, `comment_count`, `etag`, `synced_at` (plus the
  composite indexes `(tenant_id, channel_id, youtube_video_id) UNIQUE` and
  `(tenant_id, channel_id, published_at DESC)`). **Deviation from the spec
  body**: the 7B spec described a "redesign" of `videos` including dropping
  placeholder columns and converting `privacy_status` from integer-enum to
  string. By Phase 7's arrival, the existing `videos` schema is NOT placeholder
  — Phase 4's bulk-operations / video_uploads / video_stats / timelines /
  playlist_items features all depend on the current shape (integer enum
  `privacy_status`, `made_for_kids`, `default_language`, etc.). A destructive
  redesign would break Phase 4 features and their specs. The 7B locked decisions
  remain honored: new YouTube metadata columns land here, the per-call audit
  lands in `youtube_api_calls`, and Phase 8's sync code can populate the new
  columns alongside the existing ones. See the migration file's comment header
  for the full reconciliation rationale.
- `app/models/youtube_api_call.rb` — `BelongsToTenant`,
  `record_timestamps = false` (append-only), `today` scope, validation on
  `client_kind`, `outcome`, `units`.
- `app/services/youtube/error.rb` (+ `quota_exhausted_error.rb`,
  `needs_reauth_error.rb`, `transient_error.rb`, `permanent_error.rb`,
  `unknown_endpoint_error.rb`, `not_configured_error.rb`) — one-class-per-file
  Zeitwerk layout.
- `app/services/youtube/quota.rb` — frozen `COSTS` hash pinned to YouTube's
  documented unit costs (`channels.list = 1`, `search.list = 100`,
  `oauth2.revoke = 0`), `DEFAULT_DAILY_BUDGET_UNITS = 10_000`,
  `cost_for(endpoint)`, `budget_remaining(google_identity)` (counts `oauth` rows
  only). `Rails.application.config.youtube_daily_budget_units` override for the
  manual quota-exhaustion drill.
- `app/services/youtube/auditor.rb` — shared `write_audit_row(...)` helper used
  by both `Client` and `PublicClient`.
- `app/services/youtube/token_refresher.rb` — POST to
  `https://oauth2.googleapis.com/token`, success path updates `access_token` /
  `expires_at` / `last_refreshed_at` (and rotates `refresh_token` if Google
  returns a fresh one), `400 invalid_grant` flips `needs_reauth: true` and
  raises `NeedsReauthError`, other failures raise `TransientError`. Pure
  function.
- `app/services/youtube/client.rb` — main client. `channels_list`,
  `videos_list`, `playlists_list`, `analytics_query` methods. Each method:
  resolves endpoint key, `ensure_token_fresh!`, pre-call budget check, retry
  loop (max 3 attempts on 5xx with exponential-backoff-with-jitter; 429 retried
  once; 401 refreshes
  - retries once; 403 quotaExceeded fail-fast; non-401/403/429 4xx →
    `PermanentError`; network errors → `TransientError`), single audit row per
    logical call. Response shape converted to Pito-shape Hashes with snake_case
    symbol keys — Google gem structs never leak past the client.
- `app/services/youtube/public_client.rb` — skeleton. `configured?` predicate;
  `channels_list(ids:, parts:)` smoke method that audits with
  `client_kind: "public"`, `google_identity_id: nil`. Phase 8 finishes the
  surface.
- `spec/services/youtube/client_spec.rb` — happy path / pre-call quota refusal /
  expired-token refresh / 401-then-401 needs_reauth / 5xx retry-and-recover /
  5xx exhaustion / 403 quotaExceeded. Uses `Google::Apis::*` stubs via
  `allow_any_instance_of` (not VCR yet — see decision 7.16).
- `spec/services/youtube/public_client_spec.rb`, `quota_spec.rb`,
  `token_refresher_spec.rb` — full unit coverage.
- `spec/factories/youtube_api_calls.rb` + traits.
- `spec/models/youtube_api_call_spec.rb` — validations + scoping.

Phase 7C — Settings → YouTube UI:

- `db/migrate/20260507300004_add_oauth_identity_to_channels.rb` — add
  `oauth_identity_id` FK + composite index. The existing `connected` boolean
  (Phase 4 placeholder) stays; this dispatch only adds the FK to
  `google_identities`.
- `app/models/channel.rb` —
  `belongs_to :oauth_identity, class_name: "GoogleIdentity", optional: true, inverse_of: :channels`.
  Existing `prevent_url_change` and seeded-channel defaults unchanged.
- `app/services/google/revoke_token.rb` — POST to
  `https://oauth2.googleapis.com/revoke`, idempotent on the "already revoked"
  path (decision 7.15: swallow the error and return true so the disconnect can
  complete locally), audit one `YoutubeApiCall` row per call. Network errors are
  also audited (`outcome: "network_error"`) without raising.
- `app/services/youtube/disconnect_channel.rb` — bulk channel-ids in, atomic
  transaction: clear `oauth_identity_id` + `connected` on each Channel, then for
  each newly-orphaned identity call `Google::RevokeToken.call(identity)` and
  `identity.destroy!` (decision 7.13: destroy the row; the historical trail
  lives in `youtube_api_calls`).
- `app/controllers/settings/youtube_controller.rb` — show / connect / channels
  actions. `show` renders the empty state when no identity, the needs_reauth
  banner state (no API call) when applicable, otherwise calls
  `Youtube::Client#channels_list(mine: true)` and reconciles with the Channels
  table. `connect` stashes the youtube_connect intent and redirects (303) to
  `/auth/google_oauth2`. `channels` builds the `channel_url` from
  `youtube_channel_id`, `find_or_initialize_by(channel_url:)`, flips
  `oauth_identity_id` + `connected: true`, surfaces flash.
- `app/controllers/deletions_controller.rb` — extend with
  `show_youtube_connection` (renders an action-screen confirmation page) and
  `destroy_youtube_connection` (invokes `Youtube::DisconnectChannel`). The
  `before_action :load_items` is now skipped when
  `params[:type] == "youtube_connection"`.
- `config/routes.rb` — `delete "deletions/youtube_connection/:ids"`, plus
  `settings/youtube` show / connect / channels routes.
- `app/views/settings/youtube/show.html.erb` + `_channel_row.html.erb` +
  `_needs_reauth_banner.html.erb` — bracketed link conventions throughout
  (`[ connect ]`, `[ disconnect ]`, `[ reconnect ]`,
  `[ connect google account ]`, `[ reconnect google account ]`). The banner uses
  red (`#cc0000`) per decision 7.12 — failure-state carve-out. **TODO for
  docs-keeper agent**: add a one-line note to `docs/design.md` documenting the
  failure-state carve-out (red is allowed for failure-state banners, not just
  destructive actions).
- `app/views/deletions/show_youtube_connection.html.erb` — confirmation page
  using `shared/_action_screen.html.erb` with `[ confirm disconnect ]` (red) and
  `[ cancel ]`.
- `app/views/settings/index.html.erb` — added a 9th pane ("google") reflecting
  connection state: connected email + last_authorized_at when present, "no" when
  absent, with a `[ manage youtube ]` bracketed link to the dedicated Settings →
  YouTube page.
- `app/controllers/settings_controller.rb` — load `@google_identity` for the new
  pane.
- `spec/services/youtube/disconnect_channel_spec.rb`,
  `spec/services/google/revoke_token_spec.rb` — full coverage of bulk
  disconnect, identity-preservation when other channels reference, idempotent
  already-revoked path.
- `spec/requests/settings/youtube_spec.rb` — empty state, needs_reauth banner
  state (no API call), happy path with `[ connect ]` / `[ disconnect ]`,
  quota-exhausted graceful fallback, channel connect (find_or_create
  idempotent), disconnect confirmation page renders, DELETE clears + destroys
  identity.
- `spec/requests/settings_spec.rb` — pane count expectation updated 8 → 9.

**Decisions made / honored (locked):**

- 7.4 (sign-in flow target): Phase 7 leaves the sign-in callback branch as a
  TODO + redirect to `root_path`; Phase 12 will own real session establishment.
  A spec asserts the TODO marker is present in the controller source.
- 7.5 (per-identity quota): `Quota.budget_remaining(identity)` sums today's
  `oauth` rows for the given identity only. PublicClient rows are bucketed under
  `client_kind: "public"` and ignored by the OAuth budget.
- 7.6 (fail-fast on quota exhaustion): no retry / backoff / queueing for
  `QuotaExhaustedError`. Phase 8 owns the queue-and-retry-tomorrow path on top.
- 7.8 (one row per logical call): the retry loop in `Youtube::Client` collapses
  5xx-then-success into a single success row. Per-attempt detail is Phase 11
  work.
- 7.9 (gem pin): `google-apis-youtube_v3 (0.64.0)` and
  `google-apis-youtube_analytics_v2 (0.18.0)` (already in the bundle from Alpha;
  bundler-audit clean).
- 7.11 (one identity per user): schema permits N (`(tenant_id, user_id)` is
  non-unique), Beta UI enforces 1.
- 7.12 (banner color): red used for the needs_reauth banner; carve-out
  documented above for the docs-keeper.
- 7.13 (disconnect lifecycle): destroy the GoogleIdentity row on full
  disconnect; audit trail lives in `youtube_api_calls`.
- 7.15 (already-revoked idempotent): `Google::RevokeToken` swallows "token
  already invalid" and audits the failure; `DisconnectChannel` proceeds with the
  local destroy regardless.
- 7.16 (test fixture strategy): WebMock stubs against canned response shapes are
  the source of truth for the spec suite in this dispatch. VCR cassettes
  recorded against the user's real Google account replace them in a follow-up
  post-Phase-7 cassette-recording session — that session is the gate before
  Phase 8 (Data Sync). `spec/support/google_stubs.rb` documents the strategy +
  sensitive-data filter list.

**Deviations from the spec body (with rationale):**

- `videos` redesign → additive only. The 7B spec described a destructive
  "redesign" of the `videos` table including dropping placeholder columns and
  converting `privacy_status` integer-enum to string. By Phase 7's arrival, the
  existing schema is NOT placeholder — Phase 4's bulk operations / video_uploads
  / video_stats / timelines / playlist_items features all depend on the current
  shape. A destructive redesign would break Phase 4 features and their specs.
  Resolution: add the truly new YouTube metadata columns (`view_count`,
  `like_count`, `comment_count`, `etag`, `synced_at`) plus the composite
  uniqueness/index per the spec, leave the rest of the schema alone. The
  migration file's header documents this in detail.
- Credentials block name: spec uses `:google`; the user's pre-existing populated
  block is `:google_oauth`. Honored the existing structure.
- OmniAuth callback path: the gem default is `/auth/google_oauth2/callback`; the
  Google Cloud Console is registered with `/auth/google/callback`. The OmniAuth
  initializer pins `callback_path: "/auth/google/callback"` to align everything.
  The Rails route at the same path captures the callback after OmniAuth's
  middleware places `omniauth.auth` in env.

**Test surface added (this dispatch):**

- 21 model specs (GoogleIdentity, YoutubeApiCall, Channel Phase 7 additions).
- 28 service specs (Quota, TokenRefresher, Client, PublicClient, RevokeToken,
  DisconnectChannel).
- 24 request specs (Auth::GoogleCallbacks, Settings::Youtube,
  /deletions/youtube_connection).
- 1 system spec (full OAuth happy path under OmniAuth test_mode).

Total suite: 1751 examples, 0 failures (up from 1683 pre-dispatch).

**Validation:**

- `bundle exec rspec` — 1751 examples, 0 failures.
- `bundle exec rubocop` — 410 files, 0 offenses.
- `bundle exec brakeman -q -A -w1` — no new warnings; the 7 pre-existing items
  (1 ForceSSL, 1 VerbConfusion, 5 Unscoped Find) are unchanged by this dispatch.
- `bundle exec bundler-audit check` — no vulnerabilities found.
- `bin/rails db:migrate` + `db:test:prepare` — migrations apply cleanly forward;
  reversibility verified by Rails' default `change` block.

**Open follow-ups (post-dispatch, not blocking):**

1. **Cassette-recording session** — the user runs the OAuth flow end-to-end
   against their real Google account; cassettes replace the WebMock stubs in
   `spec/services/youtube/client_spec.rb` etc. Sensitive-data filters declared
   in `spec/support/google_stubs.rb` apply. This is the gate before Phase 8
   (Data Sync).
2. **Docs-keeper dispatch** — three docs to land:
   - `docs/architecture.md` — Google OAuth section + YouTube client
     architecture + quota / audit table reference.
   - `docs/youtube_quota.md` (new) — per-endpoint quota costs, daily budget,
     exhaustion behavior.
   - `docs/setup.md` — Google Cloud project setup checklist for fresh installs.
   - `docs/design.md` — one-line carve-out note in the color section: red is
     allowed for failure-state banners, not just destructive actions (decision
     7.12).
3. **Manual playbook** — the user exercises the full happy path (connect Google
   → list channels → connect a channel → see it in /channels → disconnect → see
   banner on revoke-from-Google → reconnect). The manual checklist is in
   `plan.md` §"Validation".

**Manual test plan (for the user, before commit):**

1. `bin/dev` — Web Puma + Sidekiq + Tailwind start.
2. Visit `https://app.pitomd.com/settings/youtube`. State is "no google account
   connected".
3. Click `[ connect google account ]`. Bounce through Google consent; approve
   `youtube.readonly` + `yt-analytics.readonly`. Land back at
   `/settings/youtube`.
4. Page now shows the connected email, scopes, last_authorized_at, and the table
   of YouTube channels under the account.
5. Click `[ connect ]` on one channel. Verify in `bin/rails console`:
   ```ruby
   c = Channel.connected.last
   c.attributes.slice("channel_url", "oauth_identity_id", "connected")
   # => { "channel_url" => "https://www.youtube.com/channel/UC...",
   #      "oauth_identity_id" => 1, "connected" => true }
   ```
6. From `psql`: `SELECT access_token FROM google_identities;` — confirm the
   value is ciphertext, NOT a plaintext bearer token.
7. Force token refresh:
   ```ruby
   GoogleIdentity.last.update!(expires_at: 5.minutes.ago)
   Youtube::Client.new(GoogleIdentity.last).channels_list(mine: true, parts: %i[snippet])
   GoogleIdentity.last.last_refreshed_at # => Time.current-ish
   ```
8. Force quota exhaustion:
   ```ruby
   Rails.application.config.youtube_daily_budget_units = 0
   Youtube::Client.new(GoogleIdentity.last).channels_list(mine: true, parts: %i[snippet])
   # => raises Youtube::QuotaExhaustedError
   YoutubeApiCall.last.outcome     # => "quota_exceeded"
   YoutubeApiCall.last.http_status # => nil (refused before HTTP)
   Rails.application.config.youtube_daily_budget_units = 10_000
   ```
9. Force `needs_reauth`:
   - Visit https://myaccount.google.com/permissions and revoke Pito's grant.
   - `GoogleIdentity.last.update!(expires_at: 5.minutes.ago)`
   - `Youtube::Client.new(GoogleIdentity.last).channels_list(mine: true, parts: %i[snippet])`
     — raises `Youtube::NeedsReauthError`.
   - `GoogleIdentity.last.needs_reauth?` => `true`.
   - Reload `/settings/youtube` — the red banner shows. The YouTube channel list
     is NOT fetched (verify via
     `YoutubeApiCall.where(created_at: 30.seconds.ago..)`).
   - Click `[ reconnect google account ]`. Re-authorize. Banner clears.
10. Disconnect:
    - On `/settings/youtube`, click `[ disconnect ]` next to a connected
      channel. Confirmation page renders. Click `[ confirm disconnect ]`.
    - `Channel.find(...)` still exists with `oauth_identity_id: nil`,
      `connected: false`.
    - If the channel was the only one referencing the identity,
      `GoogleIdentity.count` drops by 1; otherwise stays.
11. Already-revoked disconnect (idempotent path):
    - Revoke at https://myaccount.google.com/permissions first.
    - `Youtube::DisconnectChannel.call(channel_ids: [Channel.connected.first.id])`.
    - The `GoogleIdentity` row is destroyed; the audit row records
      `outcome: "client_error"` for the revoke call. No exception bubbles up.
12. `bundle exec rspec` — green.

## 2026-05-07 — Path A2 (literal full retract): thin Channel/Video records

**State at start:** Phase 7 (A/B/C) had landed. Channels carried Phase 4
placeholder columns (`connected`, `syncing`) PLUS Phase 7B additive metadata
columns (`title`, `description`, `subscriber_count`, `video_count`,
`view_count`, `thumbnail_url`, `etag`, `synced_at`). Videos carried full Phase 4
metadata (`title`, `description`, `published_at`, `duration_seconds`,
`privacy_status`, `made_for_kids`, `default_language`, `tags`,
`scheduled_publish_at`, `category_id`, `like_count`, `comment_count`,
`view_count`, `etag`, `synced_at`, `thumbnail_url`). The user opened a
10-question dispatch about how to retract Phase 4's speculative metadata caching
so Phase 8+ can rebuild from intentional foundations. The user answered all 10
questions and chose **Path A2 (literal full retract)** with two specific scopes:

- Meilisearch reduced to a stub (keep the engine + `SearchController` +
  `Mcp::Tools::SearchContent`, drop only Video's `searchable :*` /
  `filterable :*` declarations). Search is a working surface that returns
  nothing for Video.
- Charts retired entirely (top-videos chart + anything else that depends on
  dropped columns). The user said "they served their purpose."

**Inputs:** the Path A2 dispatch instructions (pasted in-session, not a spec
file under `specs/`). Maps to the question-by-question answers the user gave.

**Final target schema (achieved):**

`channels`:
`id, tenant_id, channel_url, star, oauth_identity_id, last_synced_at, created_at, updated_at`.
Dropped: `connected`, `syncing`, `title`, `description`, `subscriber_count`,
`video_count`, `view_count`, `thumbnail_url`, `etag`, `synced_at`. The composite
indexes on `(tenant_id, connected)` and `(tenant_id, syncing)` were removed
alongside the columns.

`videos`:
`id, tenant_id, youtube_video_id, channel_id, star, oauth_identity_id, last_synced_at, created_at, updated_at`.
Dropped: `title`, `description`, `published_at`, `duration_seconds`,
`privacy_status`, `made_for_kids`, `default_language`, `tags`,
`scheduled_publish_at`, `category_id`, `like_count`, `comment_count`,
`view_count`, `etag`, `synced_at`, `thumbnail_url`. The composite index
`(tenant_id, channel_id, published_at DESC)` was removed; the unique index
`(tenant_id, channel_id, youtube_video_id)` survives. Added: `oauth_identity_id`
(FK to `google_identities`, nullable), `star` (boolean, default false),
`(tenant_id, star)` index. `last_synced_at` already existed from a Phase 4
placeholder migration and was preserved.

**Migrations (all reversible, forward + back tested):**

- `db/migrate/20260507400000_drop_youtube_metadata_from_channels.rb`
- `db/migrate/20260507400001_drop_youtube_metadata_from_videos.rb`
- `db/migrate/20260507400002_add_oauth_identity_and_last_synced_to_videos.rb`
  (the `last_synced_at` column already existed; the migration adds
  `oauth_identity_id` + `star` only.)

**Phase 4 features that survive vs are retracted:**

| Feature                                                                              | Status                           | Notes                                                                                                                                                                             |
| ------------------------------------------------------------------------------------ | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `video_uploads`                                                                      | Survives                         | Separate model with FK to Video. Untouched by this dispatch.                                                                                                                      |
| `video_stats`                                                                        | Survives                         | Time-series model; doesn't depend on Video metadata.                                                                                                                              |
| `timelines`                                                                          | Survives                         | `link_or_create_video_for_upload` no longer assigns `video.title = "Pending sync — …"`; Video is just `youtube_video_id + channel`.                                               |
| `playlist_items`                                                                     | Survives                         | Join table. Untouched.                                                                                                                                                            |
| Video search                                                                         | Stubbed                          | Video declares no `searchable :*` / `filterable :*`. Search infra intact; Video index has only `id`.                                                                              |
| Video bulk-ops                                                                       | Survives                         | Bulk delete works on IDs; preview/progress views render `youtube_video_id` as the label.                                                                                          |
| Dashboard top-videos chart                                                           | Retired                          | Depended on `videos.title`. Retired entirely; Phase 8+ may rebuild.                                                                                                               |
| Other dashboard charts (daily views / views by channel / daily engagement)           | Survive                          | All read VideoStat aggregates only.                                                                                                                                               |
| Video CRUD form                                                                      | Retired                          | Routes `:new`, `:create`, `:edit`, `:update` removed. Show / index / destroy / panes / stats survive. `app/views/videos/edit.html.erb`, `new.html.erb`, `_form.html.erb` deleted. |
| Channels [connect]/[disconnect] inline toggle on /channels/:id                       | Retired                          | Pane just shows current state; connect/disconnect happens at /settings/youtube.                                                                                                   |
| Channels "syncing" filter chip + status column                                       | Retired                          | Column dropped from picker, deletions/show, syncs/show, syncs/progress, deletions/progress.                                                                                       |
| MCP `update_channel`'s `connected:` arg                                              | Retired                          | Schema drops the property entirely; `additionalProperties: false` rejects unknown keys at the protocol layer.                                                                     |
| MCP `create_video`                                                                   | Retired entirely                 | Tool file deleted (`app/mcp/tools/create_video.rb`); spec deleted.                                                                                                                |
| MCP `update_video`                                                                   | Heavy retract                    | Collapsed to `star:` only.                                                                                                                                                        |
| MCP `list_videos` / `list_channels`                                                  | Survives, retract output         | Drop metadata fields from output JSON. `list_channels` drops the `syncing:` filter arg.                                                                                           |
| MCP `get_dashboard`                                                                  | Retracts top-videos array        | Returns whatever survives.                                                                                                                                                        |
| MCP `sync_records`                                                                   | Survives, drop syncing partition | Every found record is `pending`; the "already syncing — skipped" partition is gone.                                                                                               |
| Channel seeded `connected` / `STAR_COUNT` / `CONNECTED_COUNT` / `INTERSECTION_COUNT` | Retracted                        | Seeded channels start with `oauth_identity_id: nil`; user connects through `/settings/youtube`.                                                                                   |
| Video seed metadata loop                                                             | Retracted                        | Seeded videos write `youtube_video_id + channel + (optional star)` only; VideoStat seeding stays for the dashboard charts.                                                        |

**Files created (migrations):**

- `db/migrate/20260507400000_drop_youtube_metadata_from_channels.rb`
- `db/migrate/20260507400001_drop_youtube_metadata_from_videos.rb`
- `db/migrate/20260507400002_add_oauth_identity_and_last_synced_to_videos.rb`

**Files modified (Channel-side):**

- `app/models/channel.rb` — drop `connected`/`syncing` scopes, `connected` and
  `syncing` columns. Add `Channel.connected` scope derived from
  `oauth_identity_id IS NOT NULL`. Keep `before_update :prevent_url_change` and
  the create / star callbacks (the ChannelSync stub is now a `last_synced_at`
  stamper).
- `app/decorators/channel_decorator.rb` — drop `syncing:` from JSON; derive
  `connected:` from `oauth_identity_id.present?`.
- `app/controllers/channels_controller.rb` — drop `connected`/ `syncing` from
  coerce + filter helpers; add scope-derived `connected` filter
  (`scope.where.not(oauth_identity_id: nil)`).
- `app/views/channels/_picker.html.erb` — drop the `syncing` chip and the
  syncing-status fork in the table cell.
- `app/views/channels/_pane.html.erb` — drop the inline `[connect]/[disconnect]`
  toggle; render `oauth_identity.email` when connected; switch the per-channel
  videos table to id/youtube_video_id columns. Drop the `syncing` row entirely.
- `app/views/channels/show.html.erb` — drop the `[syncing]` badge next to the
  page heading.
- `app/jobs/channel_sync.rb` — collapse to a `last_synced_at` stamper (no more
  `syncing` flag flipping).

**Files modified (Video-side):**

- `app/models/video.rb` — drop `enum :privacy_status`, drop
  `validates :title, presence: true`, drop the `searchable :*` / `filterable :*`
  lines. Keep the `Searchable` concern included (so reindex/remove hooks still
  fire). Add `belongs_to :oauth_identity, optional: true` and
  `scope :starred, -> { where(star: true) }`.
- `app/decorators/video_decorator.rb` — drop `formatted_*` helpers
  - all metadata fields. JSON shape collapses to id / youtube_video_id /
    channel_id / channel_url / star / aggregate stats / last_synced_at / trend.
- `app/controllers/videos_controller.rb` — drop `new`, `create`, `edit`,
  `update`, `video_params`. Sort allowlist drops `title` and `published_at`;
  default sort is `created_at desc`.
- `config/routes.rb` — drop `:new`, `:create`, `:edit`, `:update` from the
  `resources :videos` block.
- `app/views/videos/index.html.erb` — rewrite around id, youtube ID, channel
  URL, aggregate stats, star, last sync. Drop the `[+]` add button.
- `app/views/videos/show.html.erb` — drop the `[e]` edit link in breadcrumb
  actions.
- `app/views/videos/_pane.html.erb` — rewrite around the surviving columns;
  render `oauth_identity.email` when set.
- `app/views/videos/_add_pane_dialog.html.erb` — replace the title column with
  id + youtube_video_id.
- `app/views/videos/panes.html.erb` — pane heading reads `video #<id>` instead
  of `<title>`.
- Deleted: `app/views/videos/edit.html.erb`, `app/views/videos/new.html.erb`,
  `app/views/videos/_form.html.erb`.

**Files modified (Phase 7C rework):**

- `app/views/settings/youtube/_channel_row.html.erb` — switch the display branch
  from `pito_channel.connected?` to `pito_channel.oauth_identity_id.present?`.
- `app/controllers/settings/youtube_controller.rb` — drop
  `channel.connected = true` and `channel.title = title`. Just set
  `oauth_identity_id` + `last_synced_at` on the Channel. Drop the
  `lookup_channel_title` helper.
- `app/services/youtube/disconnect_channel.rb` — disconnect just clears
  `oauth_identity_id` (the `connected: false` half is gone with the column).
- `app/views/deletions/show_youtube_connection.html.erb` — drop the
  `<td><%= channel.title %></td>` column from the disconnect confirmation table.

**Files modified (Search stub):**

- `app/views/search/show.html.erb` — replace the video results table with a Path
  A2 caption explaining the disabled state.
- (No changes to `app/services/search/meilisearch_engine.rb`,
  `app/controllers/search_controller.rb`, or `app/mcp/tools/search_content.rb` —
  the engine surface is intact; Video declares no fields, so the index document
  has only `id`.)

**Files modified (Charts retract):**

- `app/controllers/dashboard_controller.rb` — drop the `@top_videos` query and
  `top_videos:` from the JSON shape.
- `app/views/dashboard/index.html.erb` — drop the "top videos by views" bar
  chart container.

**Files modified (MCP tools):**

- `app/mcp/tools/update_channel.rb` — drop the `connected:` schema arg; drop the
  `CONNECTED_NOT_ALLOWED` rejection (no longer applicable). Tool collapses to
  `star:` only.
- `app/mcp/tools/update_video.rb` — collapse to `star:` only; schema drops all
  metadata properties.
- Deleted: `app/mcp/tools/create_video.rb`. Video creation is Phase 8+ territory
  (connect-channel sync flow only).
- `app/mcp/tools/list_channels.rb` — drop the `syncing:` filter arg and the
  `connected: scope.where(connected: true)` branch (replaced by
  `where.not(oauth_identity_id: nil)`).
- `app/mcp/tools/list_videos.rb` — order by `created_at desc` (was
  `published_at desc`); drop `published_at` from the description.
- `app/mcp/tools/get_dashboard.rb` — drop the `top_videos` query and field.
- `app/mcp/tools/get_channel.rb` — update description to reflect the post-A2
  shape (`syncing` field gone).
- `app/mcp/tools/get_video.rb` — update description.
- `app/mcp/tools/sync_records.rb` — drop the `record.syncing? -> :skipped`
  partition. Every found record is syncable. `label_for(record, "video")`
  returns `record.youtube_video_id` (was `record.title`).
- `app/mcp/tools/delete_records.rb` — `label_for(record, "video")` returns
  `record.youtube_video_id`.

**Files modified (controllers / views shared):**

- `app/controllers/syncs_controller.rb` — drop `partition_items`,
  `@already_syncing`, `@already_syncing_ids`, the
  `before_action :partition_items` call, and the `skipped:` partition in
  `bulk_preview_json`.
- `app/views/syncs/show.html.erb` — drop the `connected` / `syncing` columns and
  the all-skipped fork.
- `app/views/syncs/progress.html.erb` — drop `connected` / `syncing` columns.
  Switch video rows to youtube_video_id.
- `app/views/deletions/show.html.erb` — drop `syncing` from the channel
  last-sync cell; switch video rows to youtube_video_id + star (instead of
  title + privacy / published / duration).
- `app/views/deletions/progress.html.erb` — same column shape changes.
- `app/views/bulk_operations/show.html.erb` — fall back through
  `try(:title) || try(:youtube_video_id) || try(:channel_url) || "(deleted)"` so
  the row label survives both Channel and Video rows.
- `app/controllers/concerns/confirmable.rb` — `scope_for("video", ids)` orders
  by `youtube_video_id` (was `title`); `label_for` returns
  `record.youtube_video_id` for Video.
- `app/controllers/timelines_controller.rb` — drop the
  `video.title = "Pending sync — …"` line in `link_or_create_video_for_upload`.
- `app/models/google_identity.rb` — add
  `has_many :videos, foreign_key: :oauth_identity_id, dependent: :nullify`.
- `app/models/saved_view.rb` — `label_for(entity)` returns `entity.id.to_s` for
  both `kind: channels` and `kind: videos` (Video has no title).

**Files modified (Seeds):**

- `db/seeds.rb` — drop `STAR_COUNT` / `CONNECTED_COUNT` / `INTERSECTION_COUNT`
  constants. Seeded Channels start with `oauth_identity_id: nil`; a starred
  subset (7 of 100) survives for the filter-chip variety. Seeded Videos write
  `youtube_video_id + channel + tenant + (i.zero? -> star)` only; the
  title-template loop and the `privacy_statuses` / `default_languages` /
  `common_tags` arrays are gone. VideoStat seeding stays so the dashboard charts
  have data.

**Specs (rewrites + drops):**

- `spec/factories/channels.rb` — drop `connected` / `syncing` defaults.
  `:connected` trait now sets `oauth_identity: association(:google_identity)`.
  `:syncing` and `:fully_loaded` traits gone.
- `spec/factories/videos.rb` — collapse to youtube_video_id + channel + star +
  last_synced_at. Drop title / description / published_at / duration_seconds /
  thumbnail_url / tags / privacy_status / default_language / made_for_kids
  defaults. Drop `:unlisted` / `:private_video` / `:scheduled` traits. Add
  `:starred` trait.
- `spec/models/channel_spec.rb` — drop `:syncing` scope test, the Phase 7
  metadata-columns block, the `:fully_loaded` factory reference. Add a
  `connected` scope test that uses `oauth_identity:`.
- `spec/models/video_spec.rb` — collapse to associations + validations on
  `youtube_video_id` + post-A2 surviving columns. Drop the `enum`,
  `validates :title`, `:scheduled` trait expectations.
- `spec/jobs/channel_sync_spec.rb` — collapse to "stamps last_synced_at" +
  missing-id no-op.
- `spec/jobs/bulk_sync_job_spec.rb` — drop the `:syncing` trait reference; the
  "skipped" item is now built by hand with `status: :skipped`.
- `spec/requests/channels_spec.rb` — drop `connected:` from the PATCH-spec, drop
  `connected:` from `:fully_loaded` references, fix the JSON shape assertion
  (`syncing` key gone), drop the inline-toggle expectations on the show page.
- `spec/requests/videos_spec.rb` — fully rewritten. Collapses to index + show +
  destroy + panes + stats. Adds "retired video CRUD routes" assertions.
- `spec/requests/syncs_spec.rb` — drop the "already syncing" partition
  expectations; every found record is syncable. JSON preview shape's `skipped`
  array is always empty.
- `spec/requests/deletions_spec.rb` — surface the `youtube_video_id` in the
  video preview row (was `title`).
- `spec/requests/dashboard_spec.rb` — drop the `top_videos` expectations from
  HTML and JSON; assert the chart container count drops to 3.
- `spec/requests/search_spec.rb` — collapse to "search renders, the surface is
  functional, but Video has nothing indexable" specs. Drop the
  title/highlight/length-cell expectations.
- `spec/requests/settings/youtube_spec.rb` — drop `connected: true` arguments to
  `create(:channel)`. Adjust the connect channel expectation to assert
  `oauth_identity_id` set + `last_synced_at` set (no `connected?` assertion).
- `spec/services/youtube/disconnect_channel_spec.rb` — drop `connected: true`
  from create calls and `connected?` assertions.
- `spec/services/search/meilisearch_engine_spec.rb` — collapse to "engine
  envelope shape stays consistent; search returns zero matches by design" specs.
- `spec/decorators/channel_decorator_spec.rb` — drop `:syncing` and
  `:fully_loaded` references. Use `oauth_identity:` for the connected case;
  assert the `syncing` JSON key is gone.
- `spec/decorators/video_decorator_spec.rb` — drop title / description /
  privacy*status / duration / published_at / thumbnail_url / tags / formatted*\*
  expectations.
- `spec/components/form_field_component_spec.rb` — switch host model from Video
  (no title now) to Project / Note (which still carry the relevant fields).
- `spec/helpers/application_helper_spec.rb` — switch `pane_breadcrumb_label`
  examples from Video (no title) to Note. Add a Video-falls-back-to-id case.
- `spec/lib/factories_smoke_spec.rb` — drop `:syncing` and `:fully_loaded`
  build-checks.
- `spec/models/concerns/searchable_spec.rb` — assert
  `Video.searchable_fields == []` and `Video.filterable_fields == []`. The
  `update!(title: …)` test uses `update!(star: true)` instead.
- `spec/models/google_identity_spec.rb` — drop `connected: true` from the
  channel-association example.
- `spec/models/saved_view_spec.rb` — video saved-view example asserts
  `entity_labels.first[:title]` is the id string (Video has no title).
- `spec/requests/bulk_operations_spec.rb` — assert the items table shows
  `video.youtube_video_id` (was `video.title`).
- `spec/mcp/tools/get_channel_spec.rb` — drop the `syncing` field expectation.
- `spec/mcp/tools/get_video_spec.rb` — drop the title / description
  expectations; assert youtube_video_id.
- `spec/mcp/tools/get_dashboard_spec.rb` — drop top_videos expectations.
- `spec/mcp/tools/list_channels_spec.rb` — drop the syncing filter test, drop
  `syncing` from the schema test, drop `:syncing` trait, drop "syncing" from the
  JSON shape assertion.
- `spec/mcp/tools/list_videos_spec.rb` — drop title expectations; assert
  youtube_video_id.
- `spec/mcp/tools/sync_records_spec.rb` — every found record is syncable;
  `skipped_count` / pre-marked-skipped expectations retired.
- `spec/mcp/tools/update_channel_spec.rb` — drop the `CONNECTED_NOT_ALLOWED`
  rejection examples; assert the schema doesn't include `connected`.
- `spec/mcp/tools/update_video_spec.rb` — fully rewritten around `star:` only.
- `spec/mcp/tools/delete_records_spec.rb` — video preview label is
  `youtube_video_id` (was `title`).
- Deleted: `spec/mcp/tools/create_video_spec.rb`.

**Validation:**

- `bundle exec rspec` — 1686 examples, 0 failures.
- `bundle exec rubocop` — 412 files, 0 offenses (3 layout offenses
  auto-corrected during the dispatch).
- `bundle exec brakeman -q -A -w1` — 3 warnings (1 ForceSSL, 1 VerbConfusion, 1
  UnscopedFind). The 7C baseline reported 7 warnings (1 ForceSSL, 1
  VerbConfusion, 5 Unscoped Find); Path A2 drops the 4 unscoped Video.find calls
  in the retired `videos#new`/`#create`/`#edit`/`#update` actions, so the
  warning count went DOWN from 7 to 3. No new findings.
- `bundle exec bundler-audit check --update` — no vulnerabilities.
- Hard-rule grep (`data-turbo-confirm`, `window.confirm`, `alert(`, `prompt(`) —
  only matches are doc comments disclaiming the prohibited usage. No actual
  usage.
- Migrations forward + back tested via `db:rollback STEP=3 && db:migrate`.

**Stubs / placeholders surviving Path A2:**

- `Search` infrastructure (Meilisearch engine, `SearchController`,
  `app/views/search/show.html.erb`, `Mcp::Tools::SearchContent`) is fully wired
  but Video declares no `searchable :*` / `filterable :*` lines, so the index
  document holds only `id` and queries return zero matches.
- `ChannelSync` is a `last_synced_at` stamper. The stub stays enqueued by
  `Channel.after_create_commit` / `after_update_commit :enqueue_sync_on_star` so
  the wiring stays exercised end-to-end. Phase 8+ swaps in the real YouTube
  sync.
- `Mcp::Tools::SyncRecords` still rejects video sync with "not yet supported";
  that's Phase 8+ territory.

**Open follow-ups:**

1. **Phase 7C settings/youtube/show fallback table** —
   `app/views/settings/youtube/show.html.erb` still has a fallback block that
   lists already-connected channels by
   `Channel.where(oauth_identity_id: @identity.id)`. The query is correct under
   Path A2 (no longer reads `connected`). Confirmed functional via the
   settings/youtube spec.
2. **Phase 8 sync plumbing** is the next dispatch. The new sync wiring will
   populate `videos.last_synced_at` / `videos.oauth_identity_id` and reintroduce
   metadata columns the user actually needs (likely starting with title +
   published_at + view_count, not the full Phase 4 set).
3. **Cassette-recording session** still pending against the user's real Google
   account (carried forward from the 7A/B/C log).
4. **Top-videos chart rebuild** — once Video carries a title (or a
   title-equivalent surface) again, the dashboard chart can come back. Phase 8+.

**Manual test plan (for the user, before commit):**

1. `bin/dev` — Web Puma + Sidekiq + Tailwind start.
2. Visit `/channels` — verify URL placeholders, no syncing chip, no syncing
   column in the table. Filter chips show only `starred` and `connected`.
3. Visit `/videos` — verify URL placeholders (youtube_video_id + channel URL
   truncated), no `[+]` add button, no `[e]` edit button on the row. Aggregate
   stats render from VideoStat.
4. Visit `/videos/<id>` — verify the show page renders without an `[e]` link in
   breadcrumb actions. The pane shows youtube ID + channel URL + last sync +
   connected (oauth identity email when set).
5. Try `GET /videos/new` and `GET /videos/<id>/edit` — both should 404 (route
   gone) or fall through to `videos#show` with a 404 for the `:new` case.
6. Visit `/settings/youtube` — verify the existing identity surface still works.
   Click `[ connect ]` on a channel; verify `Channel.last.oauth_identity_id` is
   set (not the dropped `connected` column).
7. Click `[ disconnect ]` on a connected channel; confirm via the action screen.
   Verify `Channel.find(...).oauth_identity_id` is `nil`. Idempotent —
   disconnecting an already-disconnected channel doesn't crash.
8. Visit `/search?q=anything` — verify the page renders with the "video search
   is currently disabled" caption (Path A2 stub).
9. Visit `/` (dashboard) — verify the page renders without errors and only 3
   charts (daily views / views by channel / daily engagement). Top-videos chart
   is gone.
10. `bin/rails console` — `Channel.new` and `Video.new` succeed without
    `connected` / `syncing` / `title` / `description` attribute errors. (The
    console-tenant hook is part of a separate dispatch.)
11. Run the full test suite + rubocop + brakeman locally as a final smoke.
    Already verified by this dispatch but worth re-running before commit.

### CLI dashboard retract (Path A2 follow-up)

Coordinated with the Rails dispatch that collapsed `/dashboard.json` to
counts-only
(`{video_count, channel_count, project_count, footage_count, note_count}`). The
CLI dashboard chart machinery has been retracted in lockstep so deserialization
continues to succeed against the slimmed JSON.

- `extras/cli/src/api/models.rs`: `DashboardData` slimmed to the five count
  fields. `TopVideo` and `DailyEngagement` structs deleted.
- `extras/cli/src/ui/dashboard.rs`: four chart render functions dropped. New
  render is a single bordered "dashboard" block listing the five counts as
  `key value` rows.
- `extras/cli/src/keys.rs`: range-tied keybindings (`1..5`, `h`, `l`) and the
  `set_dashboard_range` helper removed; the dashboard now has no per-screen
  keys.
- `extras/cli/src/app.rs`: `RANGES` constant, `range`, and `range_index` dropped
  from `DashboardState`. `get_dashboard()` is parameterless on the trait. HTTP
  path is `/dashboard.json` (no query string).
- `extras/cli/src/theme.rs`: `pink` color removed (only the retired
  views-by-channel chart used it).
- Tests: dashboard fixtures use the slim shape, three dashboard TUI tests cover
  dark/light theme bg + counts rendering. 124 lib + 199 bin + 20 integration =
  343 tests pass; clippy clean with
  `--all-targets --all-features -- -D warnings`. Pre-existing fmt drift in
  unrelated files left untouched.

### Rails-side chart-sweep (paired with the CLI retract above)

Companion dispatch to the CLI retract. The dashboard chart machinery has been
removed from the Rails app in full so the surfaces that fed the CLI now match
its slimmed expectations. Git history is the durable record for the prior chart
shapes — code-level scaffolding does not stay around as "remember what we had".

What was retired (and what each chart previously did, for the historical
record):

- **daily views** — `line_chart` of `VideoStat.sum(:views)` grouped by day,
  date-range filtered (`7d / 30d / 90d / 1y / all`).
- **views by channel** — multi-series `line_chart` of per-channel
  `VideoStat.sum(:views)` grouped by `(channel_id, date)`. Series labels were
  `"channel #<id>"` placeholders post Path A2 (Channel lost its synced title).
- **daily engagement** — two-series `line_chart` of likes + comments daily sums.
- **chart toolbar** — `[ 7d / 30d / 90d / 1y / all ]` bracketed range selector.
- **per-chart `[ ] sync` checkboxes** — bracketed `CheckboxComponent`s wired
  into a `chart-sync` Stimulus controller that persisted crosshair-sync opt-in
  per chart in `localStorage`.

Files modified or deleted in this dispatch:

- `app/views/dashboard/index.html.erb` — three chart blocks, the `chart-sync`
  wrapper, the `ChartToolbarComponent` render, and the per-chart `[ sync ]`
  checkboxes are gone. The data branch now renders one bracketed placeholder
  line:
  `[ dashboard reset — charts return with intentional metrics in a later phase. ]`.
  The empty-state branch (`bin/rails db:seed` copy block) is unchanged.
- `app/controllers/dashboard_controller.rb` — `RANGES`, `@daily_views`,
  `@views_by_channel`, `@daily_engagement`, `@range`, `date_range`,
  `hash_to_tuples`, and `views_by_channel_tuples` deleted. The action now sets
  `@video_count` / `@channel_count` only and the JSON branch returns
  `{video_count, channel_count}`.
- `app/mcp/tools/get_dashboard.rb` — collapsed to a status summary returning
  `{video_count, channel_count, project_count, footage_count, note_count}`. The
  `range` argument and the chart payload keys are dropped. Tool description
  updated. The Project / Footage / Note counts are added so the tool stays a
  one-shot status view as Phase 4 surfaces grow.
- `app/components/chart_toolbar_component.rb` — DELETED.
- `app/components/chart_toolbar_component.html.erb` — DELETED.
- `spec/components/chart_toolbar_component_spec.rb` — DELETED.
- `app/javascript/controllers/chart_sync_controller.js` — DELETED.
- `spec/requests/dashboard_spec.rb` — chart expectations stripped; new specs
  assert the placeholder line + the negative shape (no `data-controller`,
  `data-chart-sync-target`, `data-chart-id`, `daily views`, `views by channel`,
  `daily engagement`, `top videos`) and the counts-only JSON shape.
- `spec/mcp/tools/get_dashboard_spec.rb` — collapsed to two specs covering the
  new five-count payload (populated + empty-state).
- `app/assets/tailwind/application.css` — comment on the `.md-check-link` rule
  no longer mentions chart-sync (filter chips are the remaining user).

Plumbing left intact (per the user's "remember what we had" directive — these
are design-system surfaces that may serve future, different metrics):

- The `htmlLegend` Chart.js plugin in `app/javascript/application.js`.
- `application_helper.rb#chart_palette` (tied to the `--color-chart-N` design
  tokens).
- The `--color-chart-1..5` custom properties in
  `app/assets/tailwind/application.css`.
- `chartkick` gem in `Gemfile` and `chartkick`/`Chart.js` importmap pins.
- `spec/lint/numeric_formatting_spec.rb` — its `CHART_HELPERS` watchdog list
  passes vacuously now (no chart calls in the views).

Cross-stack contract (post-sweep) — `/dashboard.json` returns:

```json
{ "video_count": <int>, "channel_count": <int> }
```

…and the `get_dashboard` MCP tool returns:

```json
{
  "video_count": <int>,
  "channel_count": <int>,
  "project_count": <int>,
  "footage_count": <int>,
  "note_count": <int>
}
```

Test result delta vs. the 1686/0/0 Path-A2 baseline: the chart-toolbar component
spec (4 examples) is gone; the dashboard request spec was rewritten (13 examples
down to 8); the get_dashboard MCP spec was rewritten (4 examples down to 2). Net
change: -11 examples. Full suite stays green; rubocop clean; brakeman unchanged.

Manual test plan addendum:

1. Visit `/` — confirm the page renders with the bracketed placeholder line and
   no charts / no `[ 7d / 30d / 90d ]` toolbar.
2. `curl -s http://localhost:3000/dashboard.json | jq` — confirm the response is
   exactly `{"video_count": <N>, "channel_count": <N>}`.
3. Run the `pito` CLI (separate dispatch) against the running Rails server —
   confirm the dashboard screen renders the five-counts block without
   deserialization errors.

### CLI Channel + Video struct alignment (Path A2 follow-up)

Symmetric counterpart to the dashboard alignment above. The Rails Path A2
retract slimmed `Channel` and `Video` to thin YouTube-reference shapes, and
their decorators (`as_summary_json` / `as_detail_json`) emit the trimmed wire
shape. The CLI's matching Rust structs in `extras/cli/src/api/models.rs` were
still demanding the dropped metadata (`syncing` on Channel; `title`,
`privacy_status`, `duration_seconds`, `published_at` on Video) and would have
failed to deserialize against the live Rails server. This dispatch retracts the
structs in lockstep and slims every TUI consumer that touched the dropped
fields.

What landed:

- `extras/cli/src/api/models.rs`:
  - `Channel`: dropped `syncing`. Kept `id`, `tenant_id`, `channel_url`, `star`,
    `connected`, `last_synced_at`, `created_at`, `updated_at` — matches the live
    `ChannelDecorator#as_summary_json` shape (note: Rails still emits
    `connected` as a derived `"yes"` / `"no"` string from
    `oauth_identity_id.present?`, and still emits `tenant_id`, so both stay on
    the struct).
  - `Video`: dropped `title`, `privacy_status`, `duration_seconds`,
    `published_at`. Added `star` (yes/no) and `last_synced_at` (which
    `VideoDecorator` does emit). Kept `youtube_video_id`, `channel_id`,
    `channel_url`, `views`, `likes`, `comments`, `watch_time_minutes`, `trend`
    (Rails emits `trend: nil` post-A2; the field stays `Option<String>` so the
    CLI gracefully falls back to the `—` placeholder forever).
  - The struct's `oauth_identity_id` field that the dispatch goal mentioned is
    NOT on the struct — Rails hides the FK behind the derived `connected`
    boolean. Per the spec's overriding directive ("Match the Rust structs to
    whatever Rails actually emits"), the wire shape wins.
- `extras/cli/src/api/client.rs` (MockClient):
  - `seed_channels`: `syncing` field removed; the previous "channel 2 is
    mid-sync" fixture state migrates to a CLI-local `syncing_ids` HashSet on
    `MockClient` so the bulk-sync "skipped already syncing" test branch keeps
    working without a wire field that no longer exists.
  - `seed_videos`: rewritten as a thin `VideoSeed` struct table — 17 video
    fixtures with youtube id, channel id, star, counts, last_synced_at, no
    titles or privacy or durations.
  - `bulk_sync_channels`: skip-detection now reads the `syncing_ids` set instead
    of `c.syncing`; `update_channel` no longer touches the field;
    `bulk_delete_channels` clears the marker for any deleted ids.
  - `search`: filter substring now matches on `youtube_video_id` and
    `channel_url` instead of the gone `title` field. Mock unit test updated.
- `extras/cli/src/ui/channels.rs`:
  - `ChannelRow` drops `syncing`. The "syncing" animated indicator on the
    last-sync column is now driven entirely by the CLI-local `SyncAnim::ids`
    (post-confirm polling window) — there is no longer a server-side sync flag
    the wire could pass.
  - `ChannelFilter::Syncing` is gone (`f y` filter chip removed). Only `f s`
    (starred) and `f c` (connected) remain.
  - `last_sync_cell` and `last_sync_cell_animated` lose their `syncing: bool`
    parameter — the animation hooks off the CLI-local polling state.
  - Tests rewritten: time-sensitive bucket assertions replaced with structural
    checks so the suite isn't fragile against the wall clock.
- `extras/cli/src/ui/channel_detail.rs`:
  - `ChannelInfo` drops `syncing`. The "Last sync" KV row prints the relative
    time straight from `last_synced_at` (em-dash placeholder when null).
  - `ChannelVideoRow` is now
    `id, youtube_video_id, star, views, likes, comments, last_synced_at` — title
    / privacy / published / duration columns are gone. Per-row layout shows
    youtube id + star marker + counts + last sync.
- `extras/cli/src/ui/videos.rs`:
  - `VideoRow` drops `title`, `privacy_status`, `published_at`,
    `duration_seconds`. Adds `star`. Columns reshuffled: `youtube id`,
    `channel`, `★`, `views`, `trend`, `likes`, `chats`, `watch`. Trend column
    stays (Rails always emits null but we render `—`).
- `extras/cli/src/ui/video_detail.rs`:
  - `VideoInfo` rewritten around the survivors: `id`, `youtube_video_id`,
    `channel_id`, `channel_url`, `star`, `views`, `likes`, `comments`,
    `watch_time_minutes`, `last_synced_at`. The screen title becomes
    `videos › <youtube_video_id>`. Metadata pane shows youtube id, channel,
    starred, totals (views · likes · chats · watch), last sync. The recent-stats
    table (powered by VideoStat) is unchanged — that endpoint still emits
    per-day rows.
- `extras/cli/src/ui/search.rs`:
  - `SearchVideoHit`: dropped `title`, `privacy_status`, `duration_seconds`.
    Added `youtube_video_id`, `star`, `views`. Result rows render
    `youtube id  channel  ★  views`.
- `extras/cli/src/ui/operation_progress.rs`: test fixture `channel()` no longer
  sets the gone `syncing` field.
- `extras/cli/src/app.rs`:
  - All transformations (`with_client`, `refresh_channels`,
    `open_channel_detail`, `refresh_channel_detail`, `open_video_detail`,
    `perform_search`) updated to build the new TUI structs from the new API
    structs.
  - `tick`'s post-sync polling loop no longer reads `c.syncing` to decide when
    to stop. The bulk-operation progress overlay is the durable terminal-state
    signal for the user; the `SyncPolling` window's only remaining job is
    animating the row indicator on the affected rows during the first refetch
    after confirm. Single-tick clear matches near-instant `ChannelSync`
    completion in production. Deadline still enforced.
- `extras/cli/src/keys.rs`: `f y` filter binding removed alongside the retired
  `ChannelFilter::Syncing` variant.

How the screens look now:

- **Channels list:** URL · star · connected · last sync. Star and connected
  badges live; the syncing column is gone — the syncing animation only fires
  while the CLI is polling after a sync confirm.
- **Videos list:** youtube id · channel id · ★ · views · trend · likes · chats ·
  watch. No more title / privacy / duration — the row is identified by its
  YouTube id.
- **Channel detail:** unchanged KV pairs minus the syncing line; per-video rows
  show youtube id + star + counts + last sync.
- **Video detail:** title bar reads `videos › <youtube_video_id>`; metadata
  shows youtube id, channel, starred, totals line, last sync. Per-day stats
  table is untouched.
- **Search overlay:** youtube id · channel · ★ · views.

Tests / lints / fmt:

- 127 lib + 202 bin + 20 integration = 349 tests pass (delta vs the previous
  343-test baseline: +6 examples, all on the slimmed model shapes).
- `cargo clippy --all-targets --all-features -- -D warnings` clean.
- `cargo fmt --check` clean on every touched file (pre-existing fmt drift in
  unrelated files left alone per the established convention).

Cross-stack ambiguity surfaced:

- The dispatch goal's "Final shapes" block listed `oauth_identity_id` on Channel
  and dropped `tenant_id`, `connected`, `views/likes/comments/etc.` from Video.
  Rails actually emits `tenant_id` and `connected` on Channel and the full count
  set on Video. The dispatch's overriding directive ("Match the Rust structs to
  whatever Rails actually emits") settles the contradiction in favor of the wire
  shape; the goal's "Final shapes" was a more aggressive trim than the
  decorators landed. If the Rails dispatch intends to slim the decorators
  further, the CLI follows in a subsequent pass.
