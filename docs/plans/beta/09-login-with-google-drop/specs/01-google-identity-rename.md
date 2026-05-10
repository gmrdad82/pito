# Phase 9 — Login-with-Google Drop + `GoogleIdentity` → `YoutubeConnection` Rename

> **Status:** dispatched 2026-05-10. Single-lane: **rails**. Builds on Phase 8
> (`docs/plans/beta/08-tenant-drop/`) which is assumed landed before this
> dispatch executes.
>
> **Cross-references:**
>
> - `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` — ADR.
>   Sign-in-with-Google retired; Google OAuth narrows to YouTube channel
>   connection only.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — inherits
>   the destructive-and-reseed migration posture.
> - `docs/realignment-2026-05-09.md` — Resolved ambiguity §"Two structural calls
>   outside the original 10" first bullet.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — sets the User-shape and email-only login surface this spec builds on.
> - `docs/plans/beta/07-google-oauth-youtube-foundation/` — phase this partially
>   supersedes; `additions.md` and `dropped.md` already anticipate the rename in
>   narrative form.
> - `CLAUDE.md` — top-level project rules (yes/no booleans, Confirmable
>   bulk-as-foundation, secrets in credentials, monospace 13px, etc.).

## Goal

Two coupled changes shipped in one dispatch:

1. **Drop the sign-in-with-Google branch outright.** The Phase 7 callback
   controller (`Auth::GoogleCallbacksController#create`) carries a
   `TODO(phase-12)` placeholder branch for sign-in. That branch never produced a
   working surface (Phase 6A landed local-password sessions; the placeholder
   redirected to root and Phase 12 — the auth-UI phase — is on indefinite hold
   per the realignment doc). ADR 0006 makes the deferral permanent: pito will
   never offer sign-in-with-Google. Remove the dormant branch, the `intent`
   dispatch in `GoogleOauthRedirect`, and the dev-only `/auth/google` redirect
   that never had a non-YouTube purpose. The login form
   (`app/views/sessions/new.html.erb`) currently has NO Google button — verify
   and document; nothing to remove there.
2. **Rename `GoogleIdentity` → `YoutubeConnection`.** The model's role narrowed
   to "an OAuth grant that gives pito access to one or more YouTube channels."
   The current name encodes the dual role (user-identity AND API grant) that ADR
   0006 retires. Rename the model, the table, the foreign key on `Channel` /
   `Video` (`oauth_identity_id` → `youtube_connection_id`), the foreign key on
   `youtube_api_calls` (`google_identity_id` → `youtube_connection_id`), every
   reference site, every spec, every factory.

The User → YoutubeConnection cardinality extends from the implicit "one row per
user" shape to an explicit `has_many` so that a single pito account holder can
connect multiple Google accounts (one grant per account; each grant covers one
or more channels). The schema already permits this (no unique on `user_id`); the
change is purely the Rails association.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                             |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Q1  | **Phase scope.** (a) Strip sign-in-with-Google plumbing from the callback controller + helpers. (b) Rename model + table + every FK column. (c) Update reference sites. (d) Test sweep.                                                                                                                                                                                              |
| Q2  | **New name.** `YoutubeConnection` (table `youtube_connections`). Foreign key column on `channels` / `videos`: `youtube_connection_id` (renamed from `oauth_identity_id`). Foreign key on `youtube_api_calls`: `youtube_connection_id` (renamed from `google_identity_id`).                                                                                                           |
| Q3  | **Login flow.** Local-password only (Phase 8's email-only form). No third-party identity buttons. The login view stays unchanged in structure; the spec only verifies the absence of any Google button.                                                                                                                                                                              |
| Q4  | **User → Connection cardinality.** `has_many :youtube_connections, dependent: :destroy`. Today's model writes `has_many :channels` from the identity side; that survives. Channels and Videos `belongs_to :youtube_connection, optional: true`.                                                                                                                                      |
| Q5  | **Doorkeeper.** Untouched. Doorkeeper handles Claude Mobile / Web MCP OAuth (per ADR 0005); Google OAuth handles pito → YouTube. Keep them strictly separate in code and in copy.                                                                                                                                                                                                    |
| Q6  | **Channel-connection UI.** Settings → YouTube (`Settings::YoutubeController` + `app/views/settings/youtube/show.html.erb`) is the entry point today and stays. The Phase 11 (Channel sync + edit) spec expands the surface; this dispatch only renames identifiers there.                                                                                                            |
| Q7  | **Migration shape.** `rename_table` + `rename_column`. Per ADR 0003's destructive-and-reseed posture the migration COULD drop and recreate, but the existing `google_identities` table carries Active Record Encryption configuration on `access_token` / `refresh_token` that survives a rename trivially. Recommendation: rename for cleanliness. (See "Migration posture" below.) |
| Q8  | **Callback URL path.** Stays at `/auth/google/callback` (matches the redirect URI registered with the Google Cloud Console — changing it requires a Google Console edit). The route name `google_oauth_callback` becomes `youtube_connection_oauth_callback` (or equivalent — see "Open questions").                                                                                 |

## Migration posture (LOCKED)

**Destructive-and-reseed, executed via rename.** Per ADR 0003 + inherited from
Phase 8:

- No production data exists. The Phase 8 dispatch already reseeds the whole DB.
- This spec's migration is therefore a CLEAN rename on a freshly-seeded schema:
  `rename_table` + `rename_column` + index renames. No data preservation
  pressure.
- Rationale for rename-not-drop-and-recreate: the existing model carries Active
  Record Encryption settings (`encrypts :access_token, :refresh_token`) and a
  non-trivial set of validations / callbacks that survive a rename trivially.
  Drop-and-recreate would force the migration to re-add `encrypts` columns as
  `text` again, the encryption metadata is keyed by table name on disk via the
  ActiveRecord::Encryption store, and the value of "starting fresh" is zero
  given there is no production data anyway.
- Rollback is explicitly NOT supported. A `down` method is permitted for Rails
  bookkeeping; document in the migration body that `rails db:rollback` is out of
  scope for testing.

If the implementation agent finds during the sweep that the rename strategy hits
a snag (e.g., Active Record Encryption stores table-name-keyed metadata that
breaks on rename), STOP and surface to the master agent — do not silently switch
strategies.

## Files touched

### Schema / migration

- `db/migrate/<NN>_rename_google_identity_to_youtube_connection.rb` (new) —
  Rails 8.1-conventional `<YYYYMMDDHHMMSS>_*.rb`. Scope:
  - `rename_table :google_identities, :youtube_connections`
  - `rename_column :channels, :oauth_identity_id, :youtube_connection_id`
  - `rename_column :videos, :oauth_identity_id, :youtube_connection_id`
  - `rename_column :youtube_api_calls, :google_identity_id, :youtube_connection_id`
  - Rename indexes (Postgres requires explicit index renames after column /
    table renames):
    - `index_google_identities_on_user_id` →
      `index_youtube_connections_on_user_id`
    - The unique partial index on `(needs_reauth = true)` →
      `index_youtube_connections_on_needs_reauth_partial`
    - The unique index on `google_subject_id` (post-Phase-8 it's a single-column
      unique index per Phase 8's index replacement table) →
      `index_youtube_connections_on_google_subject_id`
    - `index_channels_on_oauth_identity_id` →
      `index_channels_on_youtube_connection_id`
    - `index_videos_on_oauth_identity_id` →
      `index_videos_on_youtube_connection_id`
    - `index_youtube_api_calls_on_google_identity_id` →
      `index_youtube_api_calls_on_youtube_connection_id`
    - The composite indexes on `youtube_api_calls` carrying `google_identity_id`
      (post-Phase-8 those become `(youtube_connection_id, created_at)`) — rename
      the index name explicitly so the schema dump stays clean.
  - Foreign-key constraint renames. Postgres FK constraint names embed the
    source column; Rails 8 generates them as `fk_rails_<hash>` so the rename is
    implicit, but the `add_foreign_key` lines in `db/schema.rb` need the new
    column names. Verify after `db:migrate` that the schema dump shows:
    - `add_foreign_key "channels", "youtube_connections", column: "youtube_connection_id"`
    - `add_foreign_key "videos", "youtube_connections", column: "youtube_connection_id"`
    - `add_foreign_key "youtube_api_calls", "youtube_connections"`
    - `add_foreign_key "youtube_connections", "users"`
  - The implementation agent verifies whether
    `add_foreign_key "youtube_api_calls", "google_identities"` survives Phase
    8's migration with that exact reference syntax. If it does, the rename here
    flips the target table reference too.
- `db/schema.rb` — auto-regenerated. Acceptance check: zero references to
  `google_identities`, `oauth_identity_id`, `google_identity_id`.

### Models

- **Rename:** `app/models/google_identity.rb` →
  `app/models/youtube_connection.rb`.
  - Class name `GoogleIdentity` → `YoutubeConnection`.
  - Update the doc comment header to describe the connection-only role (drop the
    "Phase 7 Step A" framing; replace with a Phase 9 rename note pointing at
    this spec and ADR 0006).
  - Drop the misleading "Beta UI in 7C enforces 1 identity per user; schema
    permits N" comment — under the new shape `has_many` is the intent, not a
    Theta deferral.
  - `has_many :channels` — keep, but update `foreign_key: :oauth_identity_id` →
    `foreign_key: :youtube_connection_id` and `inverse_of: :oauth_identity` →
    `inverse_of: :youtube_connection`.
  - `has_many :videos` — same updates.
  - `has_many :youtube_api_calls` — update `foreign_key: :google_identity_id` →
    `foreign_key: :youtube_connection_id` and `inverse_of: :google_identity` →
    `inverse_of: :youtube_connection`.
  - Encryption columns / validations / scopes / instance methods all survive
    unchanged.
- **Edit:** `app/models/user.rb` — add explicit
  `has_many :youtube_connections, dependent: :destroy`. (Today the User model
  has no `has_many :google_identities` declaration; the inverse lives on
  `GoogleIdentity#belongs_to :user`. The new declaration formalizes the
  user-can-hold-multiple shape.)
- **Edit:** `app/models/channel.rb`:
  - `belongs_to :oauth_identity, class_name: "GoogleIdentity", optional: true, inverse_of: :channels`
    → `belongs_to :youtube_connection, optional: true, inverse_of: :channels`
    (no `class_name:` needed once the class name matches the association).
  - The `connected` scope: `where.not(oauth_identity_id: nil)` →
    `where.not(youtube_connection_id: nil)`.
  - Update the comment header that references "Phase 7 — Channel <->
    GoogleIdentity link" to refer to YoutubeConnection.
- **Edit:** `app/models/video.rb`:
  - `belongs_to :oauth_identity, class_name: "GoogleIdentity", optional: true` →
    `belongs_to :youtube_connection, optional: true`.
  - Update the inline comment.
- **Edit:** `app/models/youtube_api_call.rb`:
  - `belongs_to :google_identity, optional: true` →
    `belongs_to :youtube_connection, optional: true`.

### Controllers

- **Edit:** `app/controllers/auth/google_callbacks_controller.rb`:
  - **Drop the sign-in branch.** The `else` branch under
    `if intent == YOUTUBE_CONNECT_INTENT` redirects to root with a
    `TODO(phase-12)`. ADR 0006 retires the branch permanently. Replacement
    behavior: any callback hitting `/auth/google/callback` without the
    `youtube_connect` intent in session is treated as a stale / replayed
    callback and redirected to `google_oauth_failure_path` with a generic
    `"sign-in via google is not supported. log in with email and password."`
    flash. (Final copy is a copy question — see Copy section.)
  - Drop the `intent` variable / dispatch entirely; the `consume_oauth_intent`
    call now returns either `YOUTUBE_CONNECT_INTENT` (the only legitimate path)
    or `nil`. Treat `nil` as the failure path above.
  - Rename the controller class from `Auth::GoogleCallbacksController` to
    `YoutubeConnections::OauthCallbacksController` (file path:
    `app/controllers/youtube_connections/oauth_callbacks_controller.rb`).
    Rationale: the controller's only remaining job is the YouTube-connection
    callback. Naming it for its purpose, not for its provider, matches the model
    rename.
  - The `failure` action's responsibility is unchanged; it stays.
  - Update the doc comment header.
  - The class still includes `GoogleOauthRedirect` (renamed — see below) for the
    intent stash + redirect resolution.
  - `upsert_identity_for_current_user` becomes
    `upsert_youtube_connection_for_current_user`. The method body drops
    `tenant_id: Current.tenant.id` (Phase 8 already removed `Current.tenant`;
    this spec verifies the line is gone).
- **Edit:** `app/controllers/concerns/google_oauth_redirect.rb` → rename file to
  `app/controllers/concerns/youtube_connection_oauth_redirect.rb`; rename module
  `GoogleOauthRedirect` → `YoutubeConnectionOauthRedirect`.
  - `SESSION_INTENT_KEY` stays (`:google_oauth_intent` is fine — the cookie
    payload is opaque to the user). **Open question:** rename to
    `:youtube_connection_oauth_intent` for symmetry, or keep the legacy key to
    avoid invalidating any in-flight session cookies? Recommendation: rename —
    the user is a single operator and any in-flight OAuth dance can be retried.
    Surface in Open Questions for master-agent confirmation.
  - `YOUTUBE_CONNECT_INTENT` constant stays (the value is the only intent worth
    tracking).
  - `redirect_target_for_intent` simplifies: the only intent is
    `youtube_connect`; `nil` and unknown values fall through to a failure-path
    target rather than `root_path` (matches the dropped sign-in branch's
    removal).
- **Edit:** `app/controllers/settings/youtube_controller.rb`:
  - `current_identity` → `current_youtube_connection`. Updates every callsite in
    this controller's actions.
  - `GoogleIdentity.where(user_id: Current.user.id)...` →
    `YoutubeConnection.where(user_id: Current.user.id)...`. The "most recently
    authorized" ordering survives.
  - In the `channels` action: `channel.oauth_identity = identity` →
    `channel.youtube_connection = connection`. The
    `update_columns(oauth_identity_id: ...)` call →
    `update_columns(youtube_connection_id: ...)`.
  - Update doc comments and instance-variable names (`@identity` →
    `@youtube_connection`).
  - The view already references `@identity` heavily — rename the instance
    variable AND update the view (see below).
- **Edit:** `app/controllers/deletions_controller.rb`:
  - The `youtube_connection` type already uses the new noun in the URL
    (`/deletions/youtube_connection/:ids`); that route name is fine.
  - `@channels = Channel.where(id: ids).where.not(oauth_identity_id: nil)` →
    `Channel.where(id: ids).where.not(youtube_connection_id: nil)`.
  - The route helper `youtube_connection_disconnect` and its action
    `destroy_youtube_connection` already match the new noun — no change.
- **Edit:** `config/routes.rb`:
  - The `match "/auth/google/callback"` line stays (the redirect URI registered
    with the Google Cloud Console is locked — see Q8). Update the controller
    reference: `to: "auth/google_callbacks#create"` →
    `to: "youtube_connections/oauth_callbacks#create"`. Rename the route name
    `:google_oauth_callback` → `:youtube_connection_oauth_callback`.
  - The `get "/auth/failure"` line: same controller-name update; the route
    helper `:google_oauth_failure` → `:youtube_connection_oauth_failure`. Update
    every callsite (the Settings::YoutubeController's failure paths today
    reference `google_oauth_failure_path`).
  - Drop the `if Rails.env.development?` block that mounts
    `get "/auth/google", to: redirect("/auth/google_oauth2")` and the
    `:google_oauth_start` helper. ADR 0006 retires the address-bar entry point —
    the dev-only redirect existed to make sign-in-with-Google testable, which is
    no longer a thing. The YouTube connect flow goes through Settings →
    YouTube's `[ connect ]` button; no shortcut needed.
  - Update the comment block ("Phase 7 — Step A...") to point at this spec and
    ADR 0006.
  - **Acceptance check:** any unauthenticated GET to `/auth/google` in
    development returns 404 (no longer a registered route).

### Views

- **Edit:** `app/views/settings/youtube/show.html.erb` — replace every
  `@identity` with `@youtube_connection` (or whatever ivar the controller picks;
  pick one canonical name in the spec).
  - The user-facing copy `<strong>connected as:</strong> <%= @identity.email %>`
    stays — the email IS the Google account email and that's what makes the
    connection identifiable.
  - The `Channel.where(oauth_identity_id: @identity.id)` fallback line becomes
    `where(youtube_connection_id: ...)`.
  - The user-facing strings ("connected as", "scopes", "reconnect",
    "disconnect") are tenant-agnostic and unchanged unless the user requests new
    copy. Surface as a copy question — recommendation: no copy change needed.
- **Edit:** any partial or component referencing `@identity` /
  `oauth_identity_id` — enumerate via
  `git grep -l 'oauth_identity\|@identity\|GoogleIdentity\|google_identity' app/views/`.
  Likely sites: `_needs_reauth_banner.html.erb`, `_channel_row.html.erb`,
  possibly `_action_screen.html.erb`'s `youtube_connection` branch.
- **Verify (no edit needed):** `app/views/sessions/new.html.erb` contains NO
  `Sign in with Google` button or `<hr>` divider preceding one. The current
  login form already only has email + password + remember-me. The architect has
  confirmed via direct read; the implementation agent re-verifies via
  `git grep -i 'google\|google_oauth' app/views/sessions/`. Expect zero matches.
  Document the absence in the implementation log.

### MCP layer

- **Sweep:** `app/mcp/tools/*.rb` and `app/mcp/resources/*.rb` for any reference
  to `GoogleIdentity`, `google_identity`, `oauth_identity`. None expected (the
  current MCP catalog covers `list_docs`, `read_doc`, `save_note`,
  `delete_records`, `sync_records` — none of which touch the OAuth identity
  model directly), but the implementation agent runs the grep and reports.
- **Sweep:** `app/mcp/rack_app.rb`, `app/mcp/tool_auth.rb` — same expectation.
  Zero matches.

### Initializer / Doorkeeper

- **Edit:** `config/initializers/omniauth.rb` — no behavioural change to the
  OAuth dance itself. The default scope set (`openid email profile`) stays at
  the provider level for the request phase to override; the
  `Settings::YoutubeController#connect` request phase already overrides with the
  YouTube scopes. Update the doc comment header to drop the "two scope sets"
  framing — there is effectively one scope set now (the YouTube-connect set; the
  `openid email profile` default is a thin fallback that no real callsite uses
  but is kept because OmniAuth requires a default).
- **Verify:** `config/initializers/doorkeeper.rb` — untouched. The Doorkeeper
  surface and the Google OAuth surface are independent.

### Services / jobs

- **Edit:** `app/services/youtube/disconnect_channel.rb` (currently a module of
  module functions — `Youtube::DisconnectChannel.call`):
  - Rename internal variables: `affected_identity_ids` →
    `affected_connection_ids`. `revoked_identity_ids` →
    `revoked_connection_ids`.
  - Result struct field rename: `revoked_identity_ids` →
    `revoked_connection_ids`. Update every callsite.
  - `GoogleIdentity.unscoped.find_by(...)` →
    `YoutubeConnection.unscoped.find_by(...)`.
  - Update the doc comment header to refer to "youtube_connection_id" rather
    than "oauth_identity_id".
- **Edit:** `app/services/google/revoke_token.rb` — the file path itself is a
  question. The service revokes a Google OAuth token; the module name
  `Google::RevokeToken` describes what it does (call Google's revoke endpoint),
  not what the record is called. Two options:
  - **Option A (recommended):** keep `Google::RevokeToken` and the file at
    `app/services/google/revoke_token.rb`. The module name describes the
    upstream service it calls (Google), not the local model. Inside, rename the
    parameter `google_identity` → `youtube_connection` and the audit row's
    `google_identity_id: google_identity.id` →
    `youtube_connection_id: youtube_connection.id`. Update the doc comments.
  - **Option B:** rename to `Youtube::RevokeConnection` and move to
    `app/services/youtube/revoke_connection.rb`. Symmetric with
    `Youtube::DisconnectChannel`. More intrusive but more consistent.
  - Recommendation: A — the change is local to the parameter name; moving the
    module changes more surfaces for marginal gain. Surface as an Open Question;
    master agent picks.
- **Edit:** `app/services/youtube/client.rb` and any helper module:
  - The constructor `Youtube::Client.new(google_identity)` accepts a
    `GoogleIdentity` today. Rename the parameter to `youtube_connection`; update
    internal `@identity` ivar to `@connection` (or pick one canonical name and
    document in the log).
  - Audit-row writes that record `google_identity_id` → record
    `youtube_connection_id`.
  - Token-refresh path that updates `@identity.last_refreshed_at` becomes
    `@connection.last_refreshed_at`. Same for `needs_reauth` flips.
- **Edit:** `app/services/youtube/auditor.rb` (or wherever the audit row is
  written) — same treatment. The audit-row column name flip flows through
  automatically once the migration renames the column; the spec just checks the
  writes hit the new column.
- **Edit:** any other service / job referencing the old names. Implementation
  agent enumerates via
  `git grep -l 'GoogleIdentity\|google_identity\|oauth_identity' app/` and
  updates each.

### Seed

- **Edit:** `db/seeds.rb` — verify no references to `GoogleIdentity` or
  `oauth_identity_id`. Phase 7's seed surface did not create identities (the
  OAuth dance is interactive), so no changes expected. The implementation agent
  confirms via grep and reports.

### Credentials / configuration

- **No change.** `config/credentials.yml.enc` continues to hold
  `google_oauth.client_id` / `google_oauth.client_secret` / optional
  `google_oauth.redirect_uri`. The credential namespace is named for the
  upstream provider (Google), not the local model.
- The `omniauth.rb` initializer continues to read
  `Rails.application.credentials.google_oauth`.

### Documentation (post-implementation; dispatched separately to docs-keeper)

The Rails implementation does NOT touch these files. After the rails-impl
dispatch lands and the user validates, the master agent dispatches
`pito-docs-keeper` against this list:

- `docs/architecture.md` — update any mention of `GoogleIdentity` to
  `YoutubeConnection`. The "Auth Foundation deferred" section stays (no
  behavioral change to the auth model).
- `docs/auth.md` — drop any sign-in-with-Google references; clarify that Google
  OAuth is exclusively for YouTube channel connection; rename `GoogleIdentity` →
  `YoutubeConnection` throughout.
- `docs/setup.md` — keep the Google Cloud project setup section; its prose
  already describes the OAuth dance for YouTube connection. The paragraph that
  frames the dance as "the user connects their Google account so pito can read
  YouTube" is correct under the new framing; verify no stray "sign in with
  Google" prose survives.
- `docs/mcp.md` — Doorkeeper-MCP and Google-OAuth are separate; verify no
  conflation; rename any `GoogleIdentity` references.
- `CLAUDE.md` — update the "Architecture notes" section's mention of
  `GoogleIdentity` (if any survives Phase 8's docs sweep).
- `docs/plans/beta/07-google-oauth-youtube-foundation/dropped.md` — append a
  2026-05-10 entry recording: the sign-in-with-Google branch in
  `Auth::GoogleCallbacksController#create` was removed; the `GoogleIdentity`
  model was renamed to `YoutubeConnection` in Phase 9; the `/auth/google`
  dev-only redirect was retired.
- `docs/plans/beta/07-google-oauth-youtube-foundation/additions.md` — no changes
  (the additions tracker covers downstream expansion, not this rename).

These edits are listed for traceability; they are NOT part of the rails-impl
dispatch's file scope.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies:

### Schema

- [ ] `db/schema.rb` shows `create_table "youtube_connections"` (NOT
      `google_identities`).
- [ ] `db/schema.rb` shows no `oauth_identity_id` column on `channels` or
      `videos`.
- [ ] `db/schema.rb` shows no `google_identity_id` column on
      `youtube_api_calls`.
- [ ] `db/schema.rb` shows `youtube_connection_id` columns on `channels`,
      `videos`, and `youtube_api_calls`.
- [ ] `db/schema.rb` shows index names on the renamed table / columns matching
      the new names exactly (no `index_google_identities_*` survivor).
- [ ] `add_foreign_key` lines in `db/schema.rb` reference `youtube_connections`
      (not `google_identities`).
- [ ] The migration's `up` runs cleanly on a freshly-Phase-8-loaded schema:
      `bin/rails db:drop db:create db:migrate db:seed` succeeds.

### Models

- [ ] `app/models/google_identity.rb` does not exist.
- [ ] `app/models/youtube_connection.rb` exists with class `YoutubeConnection`.
- [ ] `app/models/user.rb` declares
      `has_many :youtube_connections, dependent: :destroy`.
- [ ] `app/models/channel.rb` declares
      `belongs_to :youtube_connection, optional: true, inverse_of: :channels`
      (no `class_name:` argument).
- [ ] `app/models/video.rb` declares
      `belongs_to :youtube_connection, optional: true`.
- [ ] `app/models/youtube_api_call.rb` declares
      `belongs_to :youtube_connection, optional: true`.
- [ ] `git grep 'GoogleIdentity' app/` returns zero matches.
- [ ] `git grep 'google_identity_id\|oauth_identity_id' app/` returns zero
      matches.

### Controllers / routes

- [ ] `app/controllers/auth/google_callbacks_controller.rb` does not exist.
- [ ] `app/controllers/youtube_connections/oauth_callbacks_controller.rb` exists
      with class `YoutubeConnections::OauthCallbacksController`.
- [ ] The controller's `create` action has NO sign-in branch — there is only the
      YouTube-connect path plus the failure fallback.
- [ ] `config/routes.rb` does not declare `:google_oauth_start`.
- [ ] `config/routes.rb` declares `:youtube_connection_oauth_callback` and
      `:youtube_connection_oauth_failure`.
- [ ] `bin/rails routes | grep -i 'auth/google'` shows only
      `/auth/google/callback` and `/auth/failure` (no `/auth/google` redirect).
- [ ] A development-mode GET to `/auth/google` returns 404.
- [ ] `app/controllers/concerns/google_oauth_redirect.rb` does not exist; the
      renamed concern at
      `app/controllers/concerns/youtube_connection_oauth_redirect.rb` exists
      with module `YoutubeConnectionOauthRedirect`.
- [ ] `Settings::YoutubeController` instance-variable names match the new model
      (`@youtube_connection` everywhere).
- [ ] `DeletionsController#show_youtube_connection` queries
      `youtube_connection_id` (not `oauth_identity_id`).

### Views

- [ ] `app/views/settings/youtube/show.html.erb` does not reference `@identity`
      or `oauth_identity_id`.
- [ ] `app/views/sessions/new.html.erb` does not reference `google`, `oauth`, or
      any sign-in-with-third-party copy. (This is a verification, not a change —
      the file is already clean.)
- [ ] `git grep -i 'GoogleIdentity\|google_identity\|oauth_identity' app/views/`
      returns zero matches.

### MCP / Doorkeeper

- [ ] `git grep 'GoogleIdentity\|oauth_identity' app/mcp/` returns zero matches.
- [ ] `config/initializers/doorkeeper.rb` is unchanged from Phase 8.
- [ ] OAuth flow (`/oauth/authorize` → `/oauth/token`) on the Doorkeeper surface
      still succeeds in a manual smoke against `bin/dev` (verifies the rename
      did not accidentally touch the MCP OAuth subsystem).

### Services / jobs

- [ ] `app/services/youtube/disconnect_channel.rb`'s `Result` struct uses
      `revoked_connection_ids` (not `revoked_identity_ids`).
- [ ] `app/services/google/revoke_token.rb` accepts `youtube_connection`
      parameter; audit-row writes use `youtube_connection_id`. (Or, if the user
      picked Option B for the rename: the file lives at
      `app/services/youtube/revoke_connection.rb` with module
      `Youtube::RevokeConnection`.)
- [ ] `app/services/youtube/client.rb`'s constructor accepts
      `youtube_connection`; internal references match.

### Tests

- [ ] `bundle exec rspec` passes.
- [ ] No spec references `GoogleIdentity`, `google_identity_id`, or
      `oauth_identity_id`. Verified via `git grep`.
- [ ] All new test cases enumerated below pass.
- [ ] The sign-in-with-Google placeholder branch is gone — there is no test
      asserting "sign-in callback redirects to root_path".

### Smoke

- [ ] After reseed, `Settings → YouTube` renders without error.
- [ ] After OAuth dance, a `YoutubeConnection` row exists with encrypted token
      columns.
- [ ] A connected channel survives a second connect of a different Google
      account: the second connect creates a SECOND `YoutubeConnection` row (per
      Q4 — `has_many`).

## Test sweep

Exhaustive coverage. The implementation agent owns the full sweep. Every spec
the agent touches lands in one of the three buckets: delete / update / add.
Total enumerated test cases counted at the end of this section.

### Specs to delete outright

| Path                                                             | Reason                                                                                                          |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Any test asserting "sign-in branch redirects to root_path"       | The branch is gone. Likely lives in `spec/requests/auth/google_callbacks_spec.rb` — agent enumerates and drops. |
| Any test asserting `/auth/google` (dev redirect) routes anywhere | The route is gone. Drop the spec.                                                                               |

### Specs to update (rename + drop tenant residue carried by Phase 8)

The agent enumerates the full set via
`git grep -l 'GoogleIdentity\|google_identity\|oauth_identity' spec/`. Expected
sites (non-exhaustive):

| Path                                               | Edit                                                                                                                                                                                                                  |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/factories/google_identities.rb`              | Rename file → `spec/factories/youtube_connections.rb`. Rename factory `:google_identity` → `:youtube_connection`. Update every callsite.                                                                              |
| `spec/models/google_identity_spec.rb`              | Rename file → `spec/models/youtube_connection_spec.rb`. Update class reference. (See "New tests" below for the rewritten spec body.)                                                                                  |
| `spec/models/channel_spec.rb`                      | `belong_to(:oauth_identity)` → `belong_to(:youtube_connection)`. Drop any `GoogleIdentity`-string references.                                                                                                         |
| `spec/models/video_spec.rb`                        | Same.                                                                                                                                                                                                                 |
| `spec/models/user_spec.rb`                         | Add a new `has_many(:youtube_connections).dependent(:destroy)` association assertion. (Phase 8 already replaces this file's body; this dispatch appends.)                                                             |
| `spec/models/youtube_api_call_spec.rb`             | `belong_to(:google_identity)` → `belong_to(:youtube_connection)`.                                                                                                                                                     |
| `spec/factories/channels.rb`                       | Any `oauth_identity` association → `youtube_connection`.                                                                                                                                                              |
| `spec/factories/videos.rb`                         | Same.                                                                                                                                                                                                                 |
| `spec/factories/youtube_api_calls.rb`              | `google_identity` factory reference → `youtube_connection`.                                                                                                                                                           |
| `spec/requests/auth/google_callbacks_spec.rb`      | Rename file → `spec/requests/youtube_connections/oauth_callbacks_spec.rb`. Drop the sign-in branch tests outright; rewrite remaining tests for the new controller name + ivar / route names. (See "New tests" below.) |
| `spec/requests/settings/youtube_spec.rb`           | Update every `GoogleIdentity` to `YoutubeConnection`; update every `oauth_identity_id` to `youtube_connection_id`; ivar references match.                                                                             |
| `spec/requests/deletions_spec.rb`                  | The `youtube_connection` type tests already use the right URL noun; update the column reference (`oauth_identity_id` → `youtube_connection_id`) and any `GoogleIdentity.find` lookups.                                |
| `spec/services/youtube/client_spec.rb`             | Constructor parameter rename; any direct `google_identity_id` audit-row assertion flips.                                                                                                                              |
| `spec/services/youtube/disconnect_channel_spec.rb` | Update the `Result` struct field name; rename internal variables; FactoryBot reference renames.                                                                                                                       |
| `spec/services/google/revoke_token_spec.rb`        | Parameter name; audit-row column.                                                                                                                                                                                     |
| Every other `spec/**/*.rb`                         | `git grep` reports the remaining sites; agent updates symbol-for-symbol.                                                                                                                                              |

### New tests to add (exhaustive coverage mandate)

The implementation agent writes these. Each is named explicitly so the reviewer
can check existence + behavior without guesswork.

#### `spec/models/youtube_connection_spec.rb` (rewritten — replaces `google_identity_spec.rb`)

The body mirrors the old spec, with the additions / deletions called out below.
Total enumerated test cases below: **18**.

- **Associations:**
  - `it { is_expected.to belong_to(:user) }` — preserved from old spec.
  - `it { is_expected.not_to belong_to(:tenant) }` — drop. Phase 8 already
    removed `belongs_to :tenant`; the new spec does not need a negative
    assertion (the absence is verified by the file's lack of the line).
  - **NEW** `it "has many channels via youtube_connection_id"` — create
    connection + two channels referencing it; assert `connection.channels`
    returns both.
  - **NEW** `it "has many videos via youtube_connection_id"` — same shape.
  - **NEW** `it "has many youtube_api_calls via youtube_connection_id"` — same
    shape.
  - **NEW** `it "destroying the connection nullifies its channels"` (preserves
    Phase 7's `dependent: :nullify` for channels) — the spec asserts the channel
    survives with `youtube_connection_id: nil`. **Note:** master agent's
    autonomous decision to recommend `dependent: :destroy` for the user-cascade
    conflicts with the existing `dependent: :nullify` on the connection-cascade.
    Keep `:nullify` on `YoutubeConnection has_many :channels` (channels outlive
    the connection — the user can re-connect later); use `:destroy` only on
    `User has_many :youtube_connections` (destroying a user cascades to their
    connections, which then nullify the connections' channels). Surface in Open
    Questions if the agent wants to reconsider.
  - **NEW**
    `it "destroying the user destroys all of the user's youtube_connections"` —
    `user.destroy`; assert `YoutubeConnection.where(user_id: user.id)` is empty
    AND that the user's channels still exist (their `youtube_connection_id` was
    nullified).
- **Validations:** all preserved from old spec, with one update:
  - `it "enforces uniqueness of google_subject_id"` — drop the "within tenant"
    qualifier; assert global uniqueness (matches Phase 8's index replacement
    that removed the `(tenant_id, google_subject_id)` composite in favor of
    `(google_subject_id)` alone).
- **Encryption at rest:** preserved as-is (column names did not change).
- **`#access_token_expired?`:** preserved as-is.
- **`#needs_reauth?`:** preserved as-is.
- **`#has_scope?` / `#scope_string`:** preserved as-is.
- **DROP the entire `describe "tenant scoping"` block** — Phase 8 already
  removed the concern; the spec's last block is dead code by the time this
  dispatch runs.

#### `spec/requests/youtube_connections/oauth_callbacks_spec.rb` (rewritten — replaces `auth/google_callbacks_spec.rb`)

Total enumerated test cases below: **9**.

- **YouTube-connect intent (happy):** OmniAuth mock returns a valid auth hash;
  the `youtube_connect` intent is in session; `Current.user` is set. Assert: a
  `YoutubeConnection` row is created keyed by `(user_id, google_subject_id)`;
  encrypted columns hold ciphertext; redirect lands on `settings_youtube_path`
  with a `notice`.
- **YouTube-connect intent: existing connection refreshes (happy):** same setup
  but a `YoutubeConnection` already exists for `(user_id, google_subject_id)`.
  Assert: NO new row is created (`YoutubeConnection.count` unchanged); the
  existing row's `access_token`, `last_authorized_at`, `needs_reauth: false` are
  updated; redirect to `settings_youtube_path`. (Resolves the master agent's
  open question on second-connect-same-Google-account: the recommendation is
  "refresh existing".)
- **YouTube-connect intent: second connect of a DIFFERENT Google account
  (happy):** different `google_subject_id`; a NEW `YoutubeConnection` row is
  created; the user's `youtube_connections.count` is now 2.
- **No intent in session (sad — replaced "sign-in" path):** controller redirects
  to `youtube_connection_oauth_failure_path` with the agreed flash copy (see
  Copy section). Assert: NO `YoutubeConnection` row created.
- **OmniAuth failure (sad):** `request.env["omniauth.error"]` is populated.
  Controller redirects to the failure path with a generic alert. NO row created.
- **CSRF / state-mismatch (sad):** OmniAuth's middleware rejects before the
  controller runs (preserved test from old spec). Assertion: 401 / failure path;
  no row.
- **Connect with token-revoked-mid-flight (edge — recommended new test):** the
  auth hash arrives but a subsequent `Youtube::Client#channels_list` would fail
  with `NeedsReauthError`. This test scopes to the callback ONLY; the
  channel-list call is the Settings::YoutubeController's responsibility. The
  callback creates the `YoutubeConnection` row regardless; the connection's
  `needs_reauth` flag flips later when an actual API call fails. Assert: row
  created with `needs_reauth: false`.
- **No `Current.user` in scope (edge):** the OAuth callback fires but
  `Current.user` is nil (cookie session expired). Controller redirects to the
  failure path with the "session expired" copy (preserved from current
  behavior). NO row created.
- **GET /auth/failure (preserved):** renders the failure page with the supplied
  `message` query param.

#### `spec/requests/sessions_spec.rb` (additive — Phase 8 owns the rewrite)

One additive case to assert ADR 0006:

- **Login form does NOT render any "Sign in with Google" button or
  third-party-identity divider.** GET `/login`; assert the response body
  contains NEITHER `google` NOR `oauth` (case-insensitive) NOR any
  `<hr>`-then-button-text-then-google-text sequence. This guards against
  accidental reintroduction.
- **POST /login with smuggled `google_id_token` param (flaw test):** the param
  has no effect on the response or on session creation. The login flow ignores
  it (today's controller does not read the param at all; this asserts the
  absence of accidental coupling).

Total: **2** additive cases here.

#### `spec/services/youtube/disconnect_channel_spec.rb` updates

Total: **2** new + the existing tests' rename sweep.

- **NEW** `it "returns revoked_connection_ids in the Result struct"` — preserved
  behavior under the new field name.
- **NEW** `it "destroys the YoutubeConnection row when no channels remain"` —
  the existing locked-decision behavior under the new class name; included for
  explicit coverage.

#### `spec/models/user_spec.rb` updates (additive)

Total: **2** new cases on top of Phase 8's rewrite:

- **NEW** `it "has many youtube_connections"` —
  `is_expected.to have_many(:youtube_connections).dependent(:destroy)`.
- **NEW** `it "destroying a user cascades to their youtube_connections"` —
  create user + connection; destroy user; assert connection is gone.

### Test count summary

| Spec file                                                   | New cases | Notes                                                                                                                                                |
| ----------------------------------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/models/youtube_connection_spec.rb`                    | 18        | Rewrite of the existing 13-case `google_identity_spec.rb` minus tenant-scoping (1 dropped) plus 5 new association cases plus 1 destroy-cascade case. |
| `spec/requests/youtube_connections/oauth_callbacks_spec.rb` | 9         | Rewrite of `auth/google_callbacks_spec.rb` minus the sign-in branch tests (estimated 2 dropped) plus 4 new edge cases.                               |
| `spec/requests/sessions_spec.rb`                            | 2         | Additive (Phase 8 owns the rewrite). Asserts the login form has no Google button + smuggled-param-no-op.                                             |
| `spec/services/youtube/disconnect_channel_spec.rb`          | 2         | Additive on top of the rename sweep.                                                                                                                 |
| `spec/models/user_spec.rb`                                  | 2         | Additive on top of Phase 8's rewrite.                                                                                                                |
| **Total NEW test cases**                                    | **33**    | Plus rename-only edits to every other spec touching the old names.                                                                                   |

## Manual playbook (post-implementation)

Architect outlines; reviewer fills in remaining steps after spec lands.

1. **Drop and recreate the database** (Phase 8's destructive-and- reseed posture
   is inherited):
   ```bash
   bin/rails db:drop db:create db:migrate db:seed
   ```
   Confirm the seed output prints "user: <email> (id=...)" and prints the
   dev-token banner once.
2. **Visit `/login`.** Confirm the form has email + password + remember-me only
   — no "Sign in with Google" button, no `<hr>` divider, no third-party-identity
   copy. Sign in with the seeded email + password.
3. **Visit `/settings/youtube`.** The page renders the empty state (no
   `YoutubeConnection` yet). Confirm the heading reads "settings → YouTube" and
   the only action is `[ connect ]`.
4. **Click `[ connect ]`.** OAuth dance bounces through Google's consent screen.
   Approve. Confirm the post-callback redirect lands on `/settings/youtube` with
   a `connected.` notice.
5. **Verify the `YoutubeConnection` row in `psql`:**
   ```sql
   SELECT id, user_id, email, google_subject_id, needs_reauth,
          last_authorized_at FROM youtube_connections;
   ```
   Confirm exactly one row; `needs_reauth = false`.
6. **Inspect the encrypted columns:**
   ```sql
   SELECT access_token, refresh_token FROM youtube_connections;
   ```
   Confirm the values are JSON-encoded ciphertext blobs (start with
   `{"p":"`...), NOT plaintext.
7. **Connect a channel.** From `/settings/youtube`, pick a channel from the list
   and click `[ connect ]`. Confirm in `psql`:
   ```sql
   SELECT id, channel_url, youtube_connection_id FROM channels
   WHERE youtube_connection_id IS NOT NULL;
   ```
8. **Confirm the dev-only `/auth/google` route is GONE.** Visit
   `https://app.pitomd.com/auth/google` directly — expect a 404.
9. **Confirm the sign-in branch is dead.** Hit `/auth/google/callback` directly
   without a session intent (curl or browser) — expect a redirect to the failure
   page with the agreed copy, NOT a root-path redirect.
10. **Disconnect.** From `/settings/youtube`, click `[ disconnect ]` on a
    connected channel. The action confirmation page renders (per the project's
    no-JS-confirm rule). Confirm. Verify in `psql`:
    ```sql
    SELECT id, channel_url, youtube_connection_id FROM channels
    WHERE id = <id>;
    -- Expect youtube_connection_id IS NULL.
    SELECT count(*) FROM youtube_connections;
    -- Expect 0 if no other channels referenced the connection
    -- (Youtube::DisconnectChannel destroys the row in that case).
    ```
11. **Run the full RSpec suite.**
    ```bash
    bundle exec rspec
    ```
    Confirm green. Note the spec count delta in `log.md`.
12. **Run `rubocop`:**
    ```bash
    bundle exec rubocop
    ```
    Confirm clean (or no new violations).
13. **Reviewer fills in:** any further smoke steps surfaced during the review
    pass.

## Cross-stack scope

| Surface           | Status                                                                                                                                                                                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                                                                                                                                                                                                   |
| MCP rack app      | **Verify-only.** No Google identity references expected; agent confirms via `git grep`.                                                                                                                                                                       |
| Doorkeeper        | **Out of scope.** Doorkeeper handles the Claude Mobile / Web MCP OAuth (per ADR 0005); Google OAuth is independent. Verify untouched.                                                                                                                         |
| `pito` CLI (Rust) | **Skipped.** No `GoogleIdentity` references in the CLI today (the API surface it consumes does not expose the identity model). Channel-connection UI in the CLI is a Phase 11+ surface; if any client-side reference shows up post-impl, file as a follow-up. |
| Astro / website   | **Skipped.** N/A.                                                                                                                                                                                                                                             |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **Stale-callback failure flash.** The dropped sign-in branch's replacement
   message when a callback hits without the `youtube_connect` intent in session.
   Suggested options:
   - `sign-in via google is not supported. log in with email and password.`
   - `oauth callback expired. retry from settings → youtube.`
   - `unsupported flow. retry the connect from settings → youtube.`
2. **`Settings::YoutubeController#connect` — no copy change needed.** The
   empty-state copy ("no google account connected.") and the connected-state
   copy ("connected as: ...") are already connection-framed (the noun is "google
   account", which matches the OAuth grant's identity from Google's side; the
   LOCAL noun is "youtube connection" but the user-facing wording stays in
   Google's noun because that's what the user is connecting). User confirms or
   picks a different framing.
3. **Action-confirmation page wording.** The disconnect screen currently reads
   "disconnect youtube connection" or similar (verify exact copy at
   `app/views/deletions/show_youtube_connection.html.erb` if it exists, or
   wherever the action screen lives). Confirm no copy change needed. The
   architect did not enumerate the file; the implementation agent confirms
   during the sweep.
4. **`needs_reauth` banner.** Located at
   `app/views/settings/youtube/_needs_reauth_banner.html.erb`. The copy likely
   references "google identity" or "youtube connection". User confirms whether
   to keep current wording or shift to "youtube connection".
5. **Audit-log event keys.** Current event keys in
   `Auth::GoogleCallbacksController` (none today — the controller does not call
   `audit(...)`). If the implementation agent adds audit calls during the sweep
   (recommended for the failure branch), pick keys:
   `youtube_connection.callback.succeeded`,
   `youtube_connection.callback.failed`,
   `youtube_connection.callback.stale_intent`. User confirms or picks
   alternatives.
6. **Settings → YouTube page heading.** Currently "settings → YouTube". No
   change recommended. User confirms.

## Open questions (architect cannot decide; master agent surfaces to user)

1. **Concern rename: `:google_oauth_intent` session key.** Rename to
   `:youtube_connection_oauth_intent` for symmetry, or keep the legacy key to
   avoid invalidating in-flight session cookies? Recommendation: rename. The
   user is a single operator; an in-flight OAuth dance during the deploy is
   trivially retried.
2. **`Google::RevokeToken` module rename.** Keep the module under `Google::`
   (module name describes the upstream provider it calls) or move to
   `Youtube::RevokeConnection` (symmetric with `Youtube::DisconnectChannel`)?
   Recommendation: keep the current module under `Google::` namespace — the move
   is more invasive than the rename benefit. User picks.
3. **Channels' `dependent:` semantics on `YoutubeConnection`'s
   `has_many :channels`.** Today: `:nullify` (channel survives the connection's
   destruction with `youtube_connection_id: nil`). Master agent's dispatch
   suggested `:destroy` for "clean revoke flows". The two are semantically
   different: `:nullify` lets the user re-connect a channel later by re-running
   the connect flow; `:destroy` wipes the `Channel` row entirely.
   Recommendation: keep `:nullify`. Channel `Channel#channel_url` is the
   user-facing identifier; preserving the row preserves the user's
   star/sort/saved-view state for that channel across reconnects. User confirms
   or overrides.
4. **Phase 9 vs. Phase 11 boundary.** Phase 9 (this spec) renames + strips
   sign-in. Phase 11 (Channel sync + edit) builds the real channel-connection
   UI. The current Settings → YouTube surface straddles the line: the
   controller + view exist but reference identifiers Phase 11 will expand.
   Recommendation: this dispatch only renames identifiers in the existing
   Settings → YouTube surface; Phase 11 expands the surface. User confirms.
5. **Migration shape — `rename_table` or drop-and-recreate?** Recommendation:
   rename (per "Migration posture" above). User confirms; if drop-and-recreate
   is preferred, the spec needs a second pass to re-add `encrypts` columns
   explicitly and to re-establish the FK / index set from scratch.
6. **Should the rename + sign-in-strip be split into two migrations for
   clarity?** Recommendation: ONE migration for the schema rename (single sweep
   is cleaner; the data shape doesn't change, only names). Sign-in-strip is a
   code-only change and lives entirely in controllers / routes / specs — no
   migration touches it. User confirms.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule (decide on copy + design unless real conflict; user validates on
review). The decisions below override any "TBD" / "user picks" framing in the
prior sections. Implementation agent treats these as the contract.

### Copy decisions

1. **Stale-callback failure flash.** Use exact copy:
   `sign-in via google is not supported. log in with email and password.` This
   is the message rendered on the failure path when a callback hits
   `/auth/google/callback` without the `youtube_connect` intent in session.
2. **`Settings::YoutubeController#connect` empty / connected copy.** No change.
   Keep current "no google account connected." / "connected as: ..." wording.
   The user-facing noun stays "google account" because that is what the user is
   connecting from Google's side; the local model rename to `YoutubeConnection`
   does not propagate to user-facing copy.
3. **Action-confirmation disconnect page wording.** No copy change assumed.
   Implementation agent confirms during the sweep at
   `app/views/deletions/show_youtube_connection.html.erb` (or wherever the
   action screen lives); if the existing copy is structurally fine, leave it.
4. **`needs_reauth` banner copy.** Keep current wording. No shift to "youtube
   connection" wording in user-facing prose.
5. **Audit-log event keys.** Add audit calls in the failure branch using these
   exact keys:
   - `youtube_connection.callback.succeeded`
   - `youtube_connection.callback.failed`
   - `youtube_connection.callback.stale_intent`
6. **Settings → YouTube page heading.** Keep "settings → YouTube" verbatim.

### Open-question decisions

1. **Session intent key rename.** Rename `:google_oauth_intent` →
   `:youtube_connection_oauth_intent`. Single operator; in-flight OAuth retries
   are trivial.
2. **`Google::RevokeToken` module.** Keep under `Google::` namespace. The module
   describes the upstream provider it calls, not the local model. Option A in
   the Open Questions list is the chosen path.
3. **`dependent:` on `YoutubeConnection has_many :channels`.** Keep `:nullify`.
   Concur with architect's recommendation; this preserves the Phase 7C
   "disconnect-lifecycle" decision (channels outlive connections; user can
   re-connect later, preserving star / saved-view state for that channel).
   Master agent's original dispatch had `:destroy`; that is overridden by
   prior-art respect.
4. **Phase 9 vs Phase 11 boundary.** As recommended. Phase 9 only renames
   identifiers in the existing Settings → YouTube surface. Phase 11 expands the
   surface itself.
5. **Migration shape.** `rename_table` + `rename_column`. Not drop-and-recreate.
6. **Single vs split migration.** ONE migration for the schema rename (single
   sweep is cleaner). Sign-in-strip is code-only and lives in controllers /
   routes / specs; no migration involvement.

## Non-goals (explicit)

- **Channel sync surface.** Phase 11 spec.
- **Video sync surface.** Realignment work unit 4.
- **MCP scope simplification.** Phase 10 (post-Phase-8); per ADR 0004.
- **Auth Foundation rebuild.** Deferred indefinitely; Phase 8 already declared
  sessions stay local-password-only.
- **Token rotation strategy / refresh-token expiry handling beyond what Phase 7
  already ships.** Phase 10's concern.
- **`pito` CLI parity for the channel-connection UI.** Whichever phase ships the
  CLI's channel-connection surface (likely a follow-up to Phase 11) covers it.
  Not in this dispatch.
- **Astro / website changes.** N/A.
- **Migration rollback testing.** Destructive-and-reseed posture; the `down`
  method (if any) is for Rails bookkeeping only.

## Implementation lane assignment

Single lane: **rails-impl** (or `pito-rails-impl`, depending on the agent
re-prefix follow-up status at dispatch time). Touches:

- `db/migrate/`, `db/schema.rb`
- `app/models/`
- `app/controllers/`, `app/controllers/concerns/`
- `app/views/settings/youtube/`, `app/views/sessions/` (verify-only)
- `app/services/youtube/`, `app/services/google/`
- `app/mcp/` (verify-only)
- `config/routes.rb`, `config/initializers/omniauth.rb`
- `spec/**`

No `extras/cli/`, no `extras/website/`, no `docs/` (that is docs-keeper's
separate dispatch after validation).

## Reviewer checkpoints (post-implementation)

The reviewer agent runs:

1. `git grep 'GoogleIdentity\|google_identity\|oauth_identity' app/ lib/ spec/ db/ config/`
   → expect zero matches except in:
   - The migration body (the column-rename migration itself).
   - `db/schema.rb` migration version comment line (if any historical reference
     survives — flag with the agent).
   - Any historical-context comment the implementation agent flags in advance.
2. `git grep -i 'sign in with google\|sign-in with google\|login with google' app/ spec/`
   → expect zero matches.
3. `bin/rails routes | grep -i auth/google` → expect exactly two lines:
   `/auth/google/callback` and `/auth/failure`. NO `/auth/google` redirect.
4. `bundle exec rspec` — green.
5. `bundle exec rubocop` — green (or no new violations).
6. `bundle exec brakeman -q` — green (or no new findings).
7. Manual playbook §1-§13 above.
8. Spec file count delta logged in
   `docs/plans/beta/09-login-with-google-drop/log.md`.
