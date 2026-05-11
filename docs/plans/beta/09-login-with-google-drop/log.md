# Phase 09 — Login-with-Google Drop · Log

## 2026-05-10 — Architect spec landed

Architect spec landed at
`docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`.

The spec covers:

- Removing the dormant sign-in-with-Google branch from
  `Auth::GoogleCallbacksController#create` and the `GoogleOauthRedirect` helper
  so `/auth/google/callback` exists exclusively for the channel-connection flow.
- Renaming `GoogleIdentity` → `YoutubeConnection` (model, table, factories,
  every reference site).
- Renaming the Channel/Video association column `oauth_identity_id` →
  `youtube_connection_id` and the matching helpers.
- Extending `User` from `has_one :google_identity` (implicit via the current
  uniqueness constraint per user) to
  `has_many :youtube_connections, dependent: :destroy`.
- Reseeding via the destructive-and-reseed posture inherited from ADR 0003
  (Phase 8) — no production data, no backfill.
- Full RSpec sweep + new test cases covering the rename and the
  channel-connection flow's edges.

Implementation lane to follow once master agent dispatches.

**Cross-references:**

- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/realignment-2026-05-09.md`
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
- `docs/plans/beta/07-google-oauth-youtube-foundation/`

## 2026-05-10 — Rails-impl pass landed

Implementation agent ran the Phase 9 spec end to end. The dispatch is one
single-lane Rails session covering the schema rename, the sign-in-with-Google
strip, every reference site, and the spec sweep.

**Migration.**
`db/migrate/20260510081047_rename_google_identity_to_youtube_connection.rb`.
`rename_table :google_identities, :youtube_connections` plus `rename_column` on
`channels.oauth_identity_id`, `videos.oauth_identity_id`, and
`youtube_api_calls.google_identity_id` → `youtube_connection_id`. Postgres
auto-rename took most of the index names; the explicit composite
`index_youtube_api_calls_on_identity_time` was hand-renamed to
`index_youtube_api_calls_on_connection_time`. Schema dump verified — zero
`google_identities` / `oauth_identity_id` / `google_identity_id` references in
`db/schema.rb`. Rollback is bookkeeping-only; the canonical reset path is
`db:drop db:create db:migrate db:seed` (ADR 0003 destructive-and-reseed).

**Models touched.**

- `app/models/google_identity.rb` → `app/models/youtube_connection.rb` (renamed;
  class body preserves encryption + validations + scope helpers; comments
  rewritten for ADR 0006 framing).
- `app/models/user.rb` — added
  `has_many :youtube_connections, dependent: :destroy`.
- `app/models/channel.rb` — `belongs_to :oauth_identity` →
  `belongs_to :youtube_connection`. Scope `connected` flipped FK.
- `app/models/video.rb` — same shape as Channel.
- `app/models/youtube_api_call.rb` — `belongs_to :google_identity` →
  `belongs_to :youtube_connection`.

**Controllers / routes.**

- `app/controllers/auth/google_callbacks_controller.rb` deleted; the `auth/`
  directory removed entirely.
- `app/controllers/youtube_connections/oauth_callbacks_controller.rb` added. The
  dormant sign-in branch is gone — any callback without the `youtube_connect`
  intent in session redirects to `youtube_connection_oauth_failure_path` with
  the locked stale-intent flash. Audit hooks added in the failure / success /
  stale-intent paths using the locked event keys
  (`youtube_connection.callback.{succeeded,failed,stale_intent}`). Helper
  `audit(...)` mirrors the SessionsController pattern (gated on
  `AUTH_AUDIT_LOGGER`).
- `app/controllers/concerns/google_oauth_redirect.rb` →
  `app/controllers/concerns/youtube_connection_oauth_redirect.rb`. Module
  renamed; `SESSION_INTENT_KEY` flipped to `:youtube_connection_oauth_intent`
  per the locked decision; `redirect_target_for_intent` now falls through to the
  failure path on nil/unknown (no more root-path placeholder).
- `app/controllers/settings/youtube_controller.rb` — `@identity` →
  `@youtube_connection`; `current_identity` → `current_youtube_connection`;
  `oauth_identity` writes flipped to `youtube_connection`.
- `app/controllers/deletions_controller.rb` —
  `@channels.where.not(oauth_identity_id: nil)` →
  `where.not(youtube_connection_id: nil)`.
- `app/controllers/settings_controller.rb` — `@google_identity` →
  `@youtube_connection`.
- `app/controllers/channels_controller.rb` — connected-filter scope flipped to
  `youtube_connection_id`.
- `config/routes.rb` — single match line stays at `/auth/google/callback` (URL
  pinned by Google Console); controller reference flipped to
  `youtube_connections/oauth_callbacks#create`; helper renamed to
  `:youtube_connection_oauth_callback`. Failure helper renamed to
  `:youtube_connection_oauth_failure`. The dev-only
  `if Rails.env.development? get "/auth/google" ...` redirect is gone;
  development GET to `/auth/google` now 404s (verified via
  `Rails.application.routes.recognize_path`).
- `config/initializers/omniauth.rb` — comment header rewritten;
  `Auth::GoogleCallbacksController` reference in `on_failure` flipped to
  `YoutubeConnections::OauthCallbacksController`.

**Views.**

- `app/views/settings/youtube/show.html.erb` — every `@identity` →
  `@youtube_connection`; the in-fallback `Channel.where(oauth_identity_id:)`
  flipped to `youtube_connection_id`. User-facing copy unchanged per locked
  decision §2.
- `app/views/settings/youtube/_channel_row.html.erb` —
  `pito_channel.oauth_identity_id` → `youtube_connection_id`.
- `app/views/settings/index.html.erb` — Google pane `@google_identity` →
  `@youtube_connection`.
- `app/views/channels/_pane.html.erb`, `app/views/videos/_pane.html.erb` —
  column reads flipped to `youtube_connection_id` / `youtube_connection.email`.
- `app/views/deletions/show.html.erb`, `app/views/deletions/progress.html.erb` —
  connected column reads flipped to `youtube_connection_id`.
- `app/views/deletions/show_youtube_connection.html.erb` — copy unchanged per
  locked decision §3.
- `app/views/sessions/new.html.erb` — verified clean (no Google copy anywhere);
  guard test added to `spec/requests/sessions_spec.rb`.

**Decorators / MCP / services.**

- `app/decorators/{channel,video}_decorator.rb` — JSON wire shape unchanged; the
  predicate flipped to `youtube_connection_id.present?`.
- `app/mcp/tools/{get_channel,list_channels}.rb` — descriptions and scope WHEREs
  flipped to `youtube_connection_id`.
- `app/services/google/revoke_token.rb` — module retained under `Google::`
  namespace per locked decision §2; parameter renamed to `youtube_connection`;
  audit-row column flipped.
- `app/services/youtube/disconnect_channel.rb` — Result struct field
  `revoked_identity_ids` → `revoked_connection_ids`; internal variable / lookup
  / model-name renames throughout.
- `app/services/youtube/client.rb` — constructor parameter renamed; `@identity`
  ivar → `@connection`; audit-row writes pass `connection:`.
- `app/services/youtube/auditor.rb` — keyword renamed (`identity:` →
  `connection:`); audit-column flipped.
- `app/services/youtube/quota.rb` — `budget_remaining` parameter renamed;
  internal WHERE flipped.
- `app/services/youtube/token_refresher.rb` — parameter renamed; internals
  follow.
- `app/services/youtube/public_client.rb` — keyword in `write_audit_row(...)`
  flipped to `connection: nil`.
- `db/seeds.rb` — comment-only update.

**Specs (added / renamed / updated).**

- Renamed: `spec/factories/google_identities.rb` →
  `spec/factories/youtube_connections.rb`; factory name flipped.
- Renamed: `spec/models/google_identity_spec.rb` →
  `spec/models/youtube_connection_spec.rb` — body rewritten with the spec's
  enumerated 18 cases (including the 5 new `has_many` association cases plus 1
  destroy-cascade case plus channel-nullify-on-destroy case). The dropped
  `tenant scoping` block is gone (Phase 8 already removed the concern).
- Renamed + rewritten: `spec/requests/auth/google_callbacks_spec.rb` →
  `spec/requests/youtube_connections/oauth_callbacks_spec.rb` — the sign-in
  branch tests are deleted; new tests cover intent-stashed-happy,
  refresh-existing-on-second-connect,
  second-connect-different-google-account-creates-second-row, scope-union,
  no-intent-stale, OmniAuth-failure, and no-Current.user-fail.
- `spec/requests/sessions_spec.rb` — two additive cases (login form has NO
  Google copy + smuggled `google_id_token` no-op).
- `spec/services/youtube/disconnect_channel_spec.rb` — every spec flipped to
  YoutubeConnection; new explicit `revoked_connection_ids`-on-Result test +
  destroy-when-no-channels test.
- `spec/factories/{channels,videos,youtube_api_calls}.rb` — refs flipped.
- `spec/models/{channel,video,user,youtube_api_call}_spec.rb`,
  `spec/decorators/channel_decorator_spec.rb`,
  `spec/services/youtube/{client,token_refresher,quota,public_client}_spec.rb`,
  `spec/services/google/revoke_token_spec.rb`,
  `spec/requests/{channels,settings/youtube}_spec.rb`,
  `spec/mcp/tools/{get_channel,list_channels}_spec.rb`,
  `spec/system/google_oauth_flow_spec.rb` — symbol-for-symbol renames.

**Quality gates.**

- `bundle exec rspec` — 1673 examples, 0 failures (was 1663 pre-Phase-9; +10 net
  after dropping the sign-in placeholder tests and consolidating the new
  association coverage).
- `bundle exec rubocop` — 421 files, 0 offenses.
- `bundle exec brakeman -q -w2` — 0 warnings, 0 errors. (Note: the brakeman
  ignore file carries two now-obsolete entries surfaced as "Obsolete Ignore
  Entries"; flagging for follow-up but not editing in this dispatch since the
  entries do not block the run.)

**Locked decisions: zero overrides.** Every copy + open-question decision in the
spec's "Master agent decisions" section was honored verbatim. The stale-callback
flash, audit-event keys, session-intent key rename, `Google::RevokeToken`
namespace retention, `dependent: :nullify` on the Channel cascade, and the
single-migration-shape rename-not-recreate strategy all landed as specified.

**Out-of-scope follow-ups (master agent dispatches separately).**

- `pito-docs-keeper` runs against `docs/architecture.md`, `docs/auth.md`,
  `docs/setup.md`, `docs/mcp.md`, `CLAUDE.md`,
  `docs/plans/beta/07-google-oauth-youtube-foundation/dropped.md` for
  narrative + spec-cross-reference rewrites.
- Brakeman ignore file (`config/brakeman.ignore`) carries two obsolete entries
  surfaced during this run; cleanup is housekeeping, not blocking.
- No Google Cloud Console action required — the locked-route URL
  `/auth/google/callback` did not change.

## 2026-05-10 — /settings/youtube layout polish (follow-up dispatch)

**Context.** Master agent dispatch following the 403 → NeedsReauthError fix
(commit ff7130c). Screenshot review surfaced a cramped pane + 3 redundant
`[reconnect]` banners + a raw `needsreauth` error token leaking into copy. This
dispatch is view-side polish on `app/views/settings/youtube/show.html.erb` and
the `_needs_reauth_banner` partial.

**Concrete changes.**

- Pane width swapped from `.pane.pane--standalone` (constrained by
  `max-width: 60ch`) to `.pane pane--wide` (904px) wrapped in a `.pane-row`,
  matching the convention used by `bundles/show.html.erb` /
  `games/show.html.erb` / `videos/show.html.erb`.
- Scopes list: now rendered as a `<ul>` with one `<li>` per scope. Each item
  shows the trailing path segment bolded (e.g. `youtube.readonly`) above the
  full URL in muted small text — no more comma-joined collapse that truncated in
  the narrow pane.
- Consolidated the 3 reconnect banners to ONE top-of-page banner. The
  pane-internal `[reconnect]` button is gone; the picker section's red banner
  collapses to a one-line muted note ("channel list will return after
  [reconnect] above.") when `needs_reauth?` is true. The `@youtube_error` picker
  banner is now gated on `!needs_reauth?` so the raw `needsreauth` class-name
  token can no longer surface in copy; the remaining internal `transient` token
  is mapped to "service temporarily unavailable" before display.
- Banner copy now differentiates two states the model can detect:
  `needs_reauth? && missing required youtube.readonly scope` reads "your google
  authorization is missing the scopes pito needs. [reconnect] to grant them.";
  the default `needs_reauth?` branch keeps the revoked-grant copy.

**Files touched.**

- `app/views/settings/youtube/show.html.erb` — pane width, scopes layout, picker
  collapse, error-token guard.
- `app/views/settings/youtube/_needs_reauth_banner.html.erb` — two copy variants
  based on `connection.has_scope?(youtube.readonly)`.
- `spec/requests/settings/youtube_spec.rb` — +8 examples (40 total): pane width,
  scope-list shape, missing-scope banner variant, no-leak guard, single-CTA
  assertion, picker-collapse copy, no-`[reconnect]`-on-healthy.
- `spec/system/google_oauth_flow_spec.rb` — assertion text refreshed.

**Gates.**

- `bundle exec rspec spec/requests/settings/youtube_spec.rb spec/system/google_oauth_flow_spec.rb`
  — 41 examples, 0 failures.
- `bundle exec rubocop spec/requests/settings/youtube_spec.rb spec/system/google_oauth_flow_spec.rb`
  — 2 files, 0 offenses. (Rubocop cannot parse `.html.erb` directly, so the two
  ERB partials are linted by ERB-Lint at the project level rather than rubocop.)
- `bundle exec brakeman -q -w2` — 0 warnings, 0 errors.

**Coordination note.** Sibling agent `a8130e77e32b5a8ad` shipped the
controller-side fix for the 403 → `[reconnect]` visibility in the same session.
That dispatch's controller flash copy ("Google account is not connected.") and
other view casing fixes ("Google" capitalized) were preserved here — spec
assertions in `spec/requests/settings/youtube_spec.rb` were re-aligned to the
new casing on the strings the controller / view dispatches own. No
controller-side edits in this polish dispatch.

**Plan checkbox tick:** none. Phase 9 has no plan.md, only this log; the parent
dispatch was an architect-level follow-up, not a planned checkbox.

**Open issues:** none from this dispatch. Pre-existing flakes / scope items
remain on the master agent's queue.
