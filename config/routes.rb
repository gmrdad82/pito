require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    expected_user = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :username)
    expected_pass = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :password)

    ActiveSupport::SecurityUtils.secure_compare(username, expected_user.to_s) &
      ActiveSupport::SecurityUtils.secure_compare(password, expected_pass.to_s)
  end
  mount Sidekiq::Web => "/sidekiq"

  # RFC 8414 — OAuth authorization server discovery metadata. Public,
  # unauthenticated JSON endpoint. Pito's Doorkeeper-issued OAuth tokens
  # (web sign-in surface) live at `/oauth/*`; this endpoint advertises
  # them. The matching `/.well-known/oauth-protected-resource` route
  # (RFC 9728) was retired with the MCP cut — Pito no longer publishes
  # an MCP-protected resource surface.
  get "/.well-known/oauth-authorization-server",
      to: "well_known#oauth_authorization_server",
      as: :oauth_authorization_server_metadata,
      defaults: { format: "json" }

  # Phase 12 — Step A (6a-sessions-and-login-ui.md) — login + logout.
  # `/login` is the user-facing convention; `DELETE /session` is the
  # singleton current-session endpoint. The plural management surface
  # (`/settings/sessions`) is handled below in the settings namespace.
  get "/login",    to: "sessions#new",     as: :login
  post "/login",   to: "sessions#create"
  delete "/session", to: "sessions#destroy", as: :session_logout

  # Phase 29 — Unit A2. Reset-password-via-2FA surface. pito does not
  # run SMTP, so there is no email-based recovery; this is the only
  # self-service browser recovery path. `new` renders the username +
  # code form; `create` verifies the username + a live TOTP code OR a
  # backup code (single-use, consumed) and mints a short-lived signed
  # reset marker; `edit` renders the set-password form behind that
  # marker; `update` applies the new password, revokes every session,
  # and redirects to `/login` (does NOT auto-log-in). Anonymous —
  # the user is not logged in. Throttled in `rack_attack.rb`.
  get   "/password/reset",      to: "password_resets#new",    as: :password_reset
  post  "/password/reset",      to: "password_resets#create"
  get   "/password/reset/edit", to: "password_resets#edit",   as: :edit_password_reset
  patch "/password/reset",      to: "password_resets#update"

  # Post-password TOTP gate. GET renders the 6-digit input form (with
  # a backup-code fallback); POST accepts either a 6-digit code or an
  # 8-char backup code, activates the session on success, and rotates
  # the session token (LD-12). POST without a pre-auth marker returns
  # 401. The marker is minted by `SessionsController#create` when the
  # password verified and the user has TOTP enabled.
  get    "/login/totp",      to: "login/totp_challenges#show",   as: :login_totp
  post   "/login/totp",      to: "login/totp_challenges#create"

  # Phase 12 — Step B (6b-doorkeeper-oauth-server.md). Doorkeeper mounts
  # `/oauth/authorize`, `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`.
  # We skip the bundled applications admin; Phase 32 follow-up
  # (2026-05-16) dropped our own `/settings/oauth_applications`
  # replacement too. Application management is now operator-only via
  # `bin/rails pito:oauth_apps:*`.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end

  # RFC 7591 — OAuth 2.0 Dynamic Client Registration. Doorkeeper 5.9
  # does not ship this endpoint; we mount our own minimal controller
  # at the conventional `POST /oauth/register` path so the Claude
  # CLI's MCP SDK (and any other DCR-aware client) can self-register.
  # The endpoint is advertised in the `/.well-known/oauth-authorization-server`
  # document via the `registration_endpoint` field.
  post "/oauth/register",
       to: "oauth/registrations#create",
       as: :oauth_register,
       defaults: { format: "json" }

  root "dashboard#index"

  # JSON-only alias for the dashboard. The pito CLI terminal client expects to
  # GET /dashboard.json (rather than /.json), so we expose a named route that
  # routes to the same controller action.
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Phase 13.3 — Top-level analytics workspace. Singular `resource`
  # (`/analytics`, not `/analytics/:id`) per master-agent decision.
  # Renders the cross-channel summary cards, the per-channel cards,
  # and the four cross-video local rollups.
  resource :analytics, only: :show, controller: "analytics"

  # Phase 24 — Google management on Channels. Bulk revoke ships under a
  # dedicated namespace because the cascade semantics differ from plain
  # delete (revoke cascades to YoutubeConnection when this was the last
  # channel; plain delete leaves the connection alone). URL pattern
  # mirrors `/deletions/:type/:ids` per CLAUDE.md bulk-as-foundation —
  # `:ids` accepts one id or N comma-separated ids.
  get  "/channels/revokes/:ids",
       to: "channels/bulk_revokes#show",
       as: :channels_bulk_revoke,
       constraints: { ids: %r{[\d,]+} }
  post "/channels/revokes/:ids",
       to: "channels/bulk_revokes#create",
       constraints: { ids: %r{[\d,]+} }

  # R2 (2026-05-25) — /videos screen removed. /channels formerly redirected
  # to /videos; now redirects to / (home). The channels sub-routes stay.
  get "/channels", to: redirect("/", status: 301)
  resources :channels, only: [ :index, :show, :destroy ] do
    collection do
      get :panes
      # Phase 24 — entry point for the Google OAuth dance kicked off
      # from the /channels Google banner (`[+ add another Google
      # account]` button). Mirrors the body of the legacy
      # Settings::YoutubeController#connect; the intent stash routes the
      # OmniAuth callback back to /channels.
      post :connect_google
    end
    member do
      # Phase 24 — per-channel revoke flow. GET renders the wide-modal
      # confirmation page; POST consumes the `confirm=yes` form and
      # enqueues `DeleteChannelDataJob`. The :revoke action class lives
      # at `ChannelRevokesController` so the channel-show controller is
      # not crowded with destructive-flow concerns.
      get  :revoke, to: "channel_revokes#show",   as: :revoke
      post :revoke, to: "channel_revokes#create"
      # Nested videos endpoint used by the pito CLI: /channels/:id/videos.json
      # returns the videos belonging to the channel as a JSON array.
      get :videos
      # Unit A0 — channel is a read-only mirror. The only mutable
      # channel attribute is `star`; it rides a dedicated singular
      # `star` resource so the general `update` action (which carried
      # the now-removed edit-form fields and the diff surface) is gone
      # entirely. PATCH /channels/:id/star. Named `channel_star` so the
      # helper reads `channel_star_path(channel)`.
      resource :star, only: :update, controller: "channels/stars",
                       as: :channel_star
    end
    # Phase 13.3 — Per-channel analytics dashboard. Singular `resource`
    # per master-agent decision (one analytics surface per channel).
    # `analytics/refresh` is a sibling POST route; the controller class
    # lives at `Channels::AnalyticsRefreshController` so it stays out of
    # the read-only `Channels::AnalyticsController` lane.
    resource :analytics, only: :show, controller: "channels/analytics"
    post "analytics/refresh",
         to: "channels/analytics_refresh#create",
         as: :analytics_refresh
    # Phase 7.5 §11g — Channel Change History View. Read-only paginated
    # list of `ChannelChangeLog` rows for this channel. `path: "history"`
    # surfaces the canonical URL term the user expects to see; the named
    # route helper is `channel_change_logs_path(channel)` →
    # `/channels/<slug>/history`. JSON branch shares the action.
    resources :change_logs, only: :index, path: "history",
                            controller: "channels/change_logs"
  end
  # R2 (2026-05-25) — /videos screen removed. Index + edit + panes + diffs
  # collection actions dropped. Member routes retained for CLI / MCP JSON API surface.
  resources :videos, only: [ :show, :destroy ] do
    member do
      # Retained for the pito CLI: /videos/:id/stats.json
      get :stats
      # Retained for MCP / CLI — publish/schedule state transitions.
      get   :pre_publish_checklist
      patch :publish
      patch :schedule
      patch :unpublish
      # Retained for MCP / CLI — diff surface.
      get   :diff
      patch :apply_diff
    end
    # Game / bundle attribution links retained for MCP / CLI.
    resources :links, only: %i[create update destroy],
                      controller: "video_game_links"

    # Per-video analytics retained for CLI / MCP.
    resource :analytics, only: :show, controller: "videos/analytics"
    post "analytics/refresh",
         to: "videos/analytics_refresh#create",
         as: :analytics_refresh
    post "analytics/retention/refresh",
         to: "videos/retention_refresh#create",
         as: :retention_refresh
  end
  # R2 (2026-05-25) — /games screen removed. Game data surfaces via home
  # panels (Pito::GamesReleasingPanelComponent, Pito::TopGamesPanelComponent).
  # Game model + IGDB services stay. Resync + search retained for CLI / MCP.
  resources :games, only: [ :show, :create, :destroy ] do
    collection do
      # IGDB search typeahead — retained for CLI / MCP.
      get :search
      # IGDB omnisearch — retained for CLI / MCP.
      get :omnisearch
      # Version-parent typeahead — retained for CLI / MCP.
      get :version_parent_search
    end
    member do
      post :resync
    end
  end
  # R2 (2026-05-25) — /bundles and /games screens removed.
  # Bundle + game controllers removed in prior R-tasks.
  # /footages formerly redirected to /games. Now redirects to / (home).
  get "/footages", to: redirect("/", status: 301)
  resources :footages, only: [ :index, :show, :edit, :update, :destroy ]


  # Phase 27 follow-up (2026-05-17) — every cover-art asset is served
  # directly by Rails' static-file middleware via the
  # `public/covers` → `<PITO_ASSETS_PATH>/covers` symlink (created by
  # `bin/rails pito:assets:setup_symlinks`). The asset layout under
  # `/covers/` is:
  #
  #   /covers/games/<game_id>/master.jpg     — normalized cover master
  #   /covers/bundles/<bundle_id>/composite.jpg — bundle composite
  #
  # The legacy auth-gated `GET /composites/:filename.jpg` route was
  # retired in the 2026-05-17 unification — bundle composites moved
  # into `/covers/bundles/<id>/composite.jpg` alongside the game
  # masters, served by the same symlink. Cover assets are non-sensitive
  # (they ship publicly on the marketing site too); the symlink
  # pattern is also prepared for `public/thumbnails` and any future
  # assets-volume sub-dirs.

  # Phase 7.5 §06 — Footage thumbnails experiment.
  #
  # Three public-read endpoints that the scrub UI (web Stimulus controller
  # AND `pito` CLI's `extras/cli/src/api/thumbnails.rs`) hit. Auth is
  # intentionally absent — the wire shape is anchored by
  # `extras/cli/tests/thumbnails_integration.rs`, which sends NO
  # `Authorization` header. Theta-phase multi-tenant work will need to
  # scope these by tenant; for the single-tenant phase the assumption is
  # that thumbnails are user-owned derived assets not worth gating.
  #
  # The `:filename` constraint enforces the `HH-MM-SS` shape at the router
  # level so path-traversal candidates (`../etc/passwd`) never reach the
  # action. The action layer reapplies the regex as defense-in-depth.
  get "/footages/:id/frames.json",
      to: "footages#frames",
      as: :footage_frames,
      defaults: { format: "json" }

  get "/footages/:footage_id/frames/m/:filename.jpg",
      to: "footages#frame_master",
      as: :footage_frame_master,
      constraints: { filename: /\d{2}-\d{2}-\d{2}/ },
      defaults: { format: "jpg" }

  get "/footages/:footage_id/frames/t/:filename.jpg",
      to: "footages#frame_thumb",
      as: :footage_frame_thumb,
      constraints: { filename: /\d{2}-\d{2}-\d{2}/ },
      defaults: { format: "jpg" }
  # Notes routes dropped 2026-05-21 (D17). The Note model + controller +
  # editor screen + filesystem mirror were all removed; deletions of
  # `note` type via `/deletions/note/:ids` no longer apply.
  # Timeline routes dropped 2026-05-21 (D18) alongside Projects.

  # Importer download endpoint — single controller, branches on Rails.env
  # in Phase B. Route shell lands now (§14 step 8 ordering); controller body
  # is part of Phase B's CLI build/distribution workstream.
  get "footage/importer/download",
      to: "footage_importer/downloads#show",
      as: :footage_importer_download

  # JSON API for the importer (Phase B). 2026-05-21 (D18) — Projects
  # dropped; the importer index/create now live on the flat `/api/footages`
  # collection routes. Member actions (update/destroy/frames) stay at
  # `/api/footages/:id`. The HTML edit/destroy flow stays at the top-level
  # `/footages/:id` (no .json).
  namespace :api do
    resources :footages, only: [ :index, :create, :update, :destroy ] do
      member do
        # Phase 7.5 §06 — bulk frame upload from the importer. Bearer-
        # authenticated via `Api::AuthConcern`. CLI integration tests
        # do NOT anchor this URL; chosen for `/api/` consistency.
        patch :frames, action: :update_frames
      end
    end
  end

  # Phase 22 — Video Import Flow. `[import]` modal on `/videos` opens
  # the channel-selection step; the four actions wire through to the
  # ImportJob ledger + per-channel keep/reject confirmation.
  namespace :imports do
    resources :channels, only: %i[index create show update]
  end

  # Phase 27 v2 spec 05 — `Users::GamesPreferencesController` retired
  # alongside the display-mode switcher and per-mode partials. `/games`
  # is a single shelves-by-letter layout; no per-user persisted display
  # preference exists anymore.

  resources :saved_views, only: [ :index, :create, :destroy ]

  # Notifications feed panel actions (home screen).
  # POST /notifications_feed/mark_read   — mark all unread as read
  # POST /notifications_feed/mark_unread — mark all read as unread
  # Handled by NotificationsFeedController (distinct from
  # NotificationsController which owns the /notifications resource).
  resources :notifications_feed, only: [] do
    collection do
      post :mark_read
      post :mark_unread
    end
  end

  # Phase 16 §3 — Notification UI. Routes:
  #   - GET    /notifications                   index (paginated, filter)
  #   - GET    /notifications/:id               detail
  #   - PATCH  /notifications/:id/read          stamp in_app_read_at
  #   - PATCH  /notifications/:id/unread        clear in_app_read_at
  #   - PATCH  /notifications/mark_read?ids=    bulk mark read (collection)
  #   - PATCH  /notifications/mark_all_read     mark every unread row read
  # Per master decision 2026-05-10 #2: collection PATCH with `?ids=` is
  # used for the bulk path because mark-read is non-destructive
  # (CLAUDE.md's `/<action>s/:type/:ids` shape is for destructive
  # actions only).
  # C19b (2026-05-22) — 3-screen taxonomy consolidation. /notifications
  # folds into the / (home) screen as a panel. Bare GET /notifications
  # redirects 301 to /. The `notifications_path` named helper still
  # resolves to `/notifications` (used heavily by the controller and
  # views for `redirect_to`); those flows now take a two-hop path
  # through the 301 until they are migrated to point at the home panel
  # directly. Detail + per-row actions (`/notifications/:id`,
  # `:read`/`:unread`, `mark_read`, `mark_all_read`, `badge`) stay
  # reachable.
  get "/notifications", to: redirect("/", status: 301)
  resources :notifications, only: %i[index show] do
    member do
      patch :read
      patch :unread
    end
    collection do
      patch :mark_read
      patch :mark_all_read
      # Phase 21 — JSON parity for CLI / MCP. Cookie-authed badge
      # endpoint that returns `{ unread_count, has_failures }`. Locked
      # decision #6: stays on the existing cookie-authed controller,
      # NOT under `/api/` (which is bearer-only via Api::AuthConcern).
      get :badge
    end
  end

  # Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
  # rename (ADR 0006). The sole legitimate flow through these routes is
  # the YouTube-connection OAuth dance; the dormant sign-in branch and
  # the dev-only `/auth/google` redirect were retired with this phase.
  #
  # The OmniAuth `callback_path` is pinned to `/auth/google/callback`
  # to match the URI registered with the Google Cloud Console; renaming
  # the URL would require a Google Console edit, so only the controller
  # class and the route helper change in this dispatch.
  match "/auth/google/callback",
        to: "youtube_connections/oauth_callbacks#create",
        via: %i[get post],
        as: :youtube_connection_oauth_callback
  get "/auth/failure",
      to: "youtube_connections/oauth_callbacks#failure",
      as: :youtube_connection_oauth_failure

  # Phase 15 §2 — Calendar views. `/calendar` renders a thin client-side
  # router page (Phase 15 calendar UX restructure): a Stimulus
  # controller reads localStorage `pito-calendar-view` and `replace`s the
  # URL with the persisted view (`/calendar/schedule` or the current
  # month grid). On fresh visits with no JS / no preference, the
  # `<meta http-equiv="refresh">` fallback drops the user on the current
  # month grid. Canonical URLs remain `/calendar/month/:year/:month`
  # and `/calendar/schedule`. Manual entries are CRUD'd under
  # `/calendar/entries`.
  # C19b (2026-05-22) — 3-screen taxonomy consolidation. /calendar folds
  # into / (home) as a panel. Bare GET /calendar redirects 301 to /.
  # Sub-routes (`/calendar/month/:year/:month`, `/calendar/schedule`,
  # `/calendar/entries/*`) stay reachable. The `calendar_root_path`
  # named helper still resolves to `/calendar`; existing breadcrumbs +
  # back-links now take a two-hop path through the 301 until they are
  # migrated to point at the home panel directly.
  get "/calendar",
      to: redirect("/", status: 301),
      as: :calendar_root
  get "/calendar/month/:year/:month",
      to: "calendar/month#show",
      as: :calendar_month,
      constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get "/calendar/schedule",
      to: "calendar/schedule#show",
      as: :calendar_schedule
  scope "/calendar" do
    resources :entries,
              controller: "calendar/entries",
              as: :calendar_entries,
              only: %i[new create show edit update] do
      collection do
        get :quick_add
      end
      member do
        # PATCH /calendar/entries/:id/note — derived/auto entries can
        # gain metadata.user_overrides notes through this endpoint.
        patch :note
        # GET /calendar/entries/:id/details_pane — calendar refactor
        # 2026-05-11. Returns the entry's details inside a Turbo Frame
        # for the month-grid / schedule-list click-to-open modal.
        get :details_pane
      end
    end
  end

  get "deletions/:type/:ids", to: "deletions#show", as: :deletions
  post "deletions/:type/:ids", to: "deletions#create"
  # Phase 15 §2 — DELETE /deletions/calendar_entry/:ids flips state to
  # :cancelled (soft-cancel per Q5). Routed through DeletionsController.
  # `defaults: { type: "calendar_entry" }` so `Confirmable#load_items`
  # finds the type for the bulk-load + scope filter.
  delete "deletions/calendar_entry/:ids",
         to: "deletions#cancel_calendar_entry",
         defaults: { type: "calendar_entry" },
         as: :calendar_entry_cancellation
  # Phase 7 — Step C. Disconnect of a YouTube connection follows the
  # `bulk-as-foundation` rule: single-channel disconnect is `:ids`
  # = one id; multi is N. The DELETE verb completes the action
  # screen confirmed at GET .../show above (the youtube_connection
  # type is dispatched specially inside DeletionsController).
  delete "deletions/youtube_connection/:ids",
         to: "deletions#destroy_youtube_connection",
         as: :youtube_connection_disconnect
  get "syncs/:type/:ids", to: "syncs#show", as: :syncs
  post "syncs/:type/:ids", to: "syncs#create"
  resources :bulk_operations, only: [ :show ] do
    member do
      get :status
    end
  end
  get "search", to: "search#show"
  # Phase 37 (2026-05-19) — "Everywhere" omnisearch endpoint. Searches
  # games + bundles + channels with context-aware section ordering
  # driven by the caller's `current_path` (or `context`) param. Backed
  # by `Search::Everywhere` (three-source orchestrator) and rendered
  # via `Search::EverywhereResultsComponent`. DISTINCT from the
  # video-only `SearchController#show` route above — built fresh per
  # the strict-independence rule (no shared controller, no shared
  # partials). See `app/services/search/everywhere.rb`.
  get "/search/everywhere", to: "everywhere_search#show",
                            as: :everywhere_search
  # C18 (2026-05-21) — /settings consolidated into / (home). The bare
  # /settings GET now 301-redirects to /. Sub-routes under
  # /settings/security/*, /settings/stack/*, /settings/notifications/*,
  # /settings/time_zone, and /settings/webhooks/* remain functional —
  # the panels' form actions and Turbo Frame paths still post to them.
  # SettingsController is kept alive (C19e cleanup will purge it).
  get "settings", to: redirect("/", status: 301)
  patch "settings", to: "settings#update"
  # Theme system removed entirely 2026-05-19 — pito is single-theme
  # now, no server-side preference, no client-side toggle. The legacy
  # `PATCH /settings/theme` route is gone for good.
  #
  # FB-63 (2026-05-20) — the single `[reindex]` action was split into
  # two distinct actions, one per stack subsystem. Each tile in the
  # Stack pane owns its own reindex trigger:
  #
  #   POST /settings/stack/meilisearch/reindex → Meilisearch only
  #   POST /settings/stack/voyage/reindex      → Voyage AI only
  #
  # The legacy `POST /settings/reindex` combined action is gone.
  post "settings/stack/meilisearch/reindex",
       to: "settings#meilisearch_reindex",
       as: :settings_stack_meilisearch_reindex
  post "settings/stack/voyage/reindex",
       to: "settings#voyage_reindex",
       as: :settings_stack_voyage_reindex

  # Phase 32 (settings refactor follow-up, 2026-05-16). The
  # `/settings/oauth_applications/*` and `/settings/tokens/*` web
  # management UIs were dropped — pito is single-user, the operator
  # manages OAuth apps + API tokens from the shell via
  # `bin/rails pito:oauth_apps:*` and `bin/rails pito:tokens:*`. The
  # Doorkeeper handshake endpoints (`/oauth/authorize`,
  # `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`) stay live
  # for the Claude Desktop OAuth client; only the management surfaces
  # are gone.
  namespace :settings do
    # Phase F3 (Beta 4, 2026-05-20) — profile self-service surface CUT.
    # Per ADR 0016, username + password management moved to operator-
    # only rake tasks: `bin/rails pito:user:rename` and
    # `bin/rails pito:user:password_set`. The `/settings/user` GET +
    # PATCH routes, the `Settings::UserController`, the profile pane
    # partial, and the standalone /settings/user page are all gone.
    # Password recovery is unchanged — the reset-via-2FA surface at
    # `/password/reset` (Phase 29 — Unit A2) still ships.

    # 2026-05-16 (sessions revamp) — the standalone `/settings/sessions`
    # index + the modal-based listing + the per-row revoke surface are
    # all gone. The sessions table renders INLINE inside the Security
    # pane on `/settings` (see `app/views/settings/_security_pane.html.erb`).
    # The bulk-revoke action endpoint stays as the single source of
    # truth for revoking sessions (1..N ids per the
    # bulk-as-foundation rule).
    #
    # 2026-05-16 (sessions revamp v3 — modal-confirm). The GET
    # confirmation screen (action-screen page at
    # `/settings/sessions/revokes/:ids`) is GONE. The confirmation
    # step is now an in-page `<dialog>` mounted on the Security pane
    # (`ConfirmModalComponent`-style — see `_security_pane.html.erb`).
    # Only the POST endpoint survives: `create` consumes `confirm=yes`
    # and revokes every targeted session before redirecting back to
    # `/settings`. The named helper stays — call sites are the modal
    # form's `action` attribute (rewritten client-side at click time)
    # and request specs.
    post "sessions/revokes/:ids",
         to: "sessions/bulk_revokes#create",
         as: :sessions_bulk_revoke,
         constraints: { ids: %r{[0-9,]+} }

    # Security surface. `resource` (singular) so the URL is
    # `/settings/security` (one dashboard per logged-in user). Post-
    # Phase-25 rollback the dashboard is 2FA-status only — the recent-
    # attempts table, auto-block list, and per-attempt detail surfaces
    # are gone along with the new-location approval flow. The TOTP
    # enrollment routes stay live.
    resource :security, only: %i[show], controller: "security"
    namespace :security do
      # Phase 32 follow-up (2026-05-16). 2FA / TOTP cleanup.
      #
      # The web surface collapsed to a single focused enrollment view.
      # Mandatory-2FA means there is no "manage" page, no `[disable]`
      # web action, and no `[manage backup codes]` control — those
      # capabilities live in operator-only rake tasks
      # (`pito:user:reset_totp` and `pito:user:regenerate_backup_codes`).
      #
      # Two routes:
      #
      #   - `totps#new`    (GET /settings/security/totp) — renders the
      #                    2-row enrollment view. Generates a fresh
      #                    seed + backup-code draft per load and
      #                    stashes it in `Rails.cache` (NOT in the
      #                    user row). Non-resumable.
      #   - `totps#create` (POST /settings/security/totp) — atomic
      #                    finalize. Reads the cached draft, verifies
      #                    the 6-digit code, and only on success
      #                    persists `totp_seed_encrypted` +
      #                    `totp_enabled_at` + backup-code rows in a
      #                    single transaction.
      #
      # The dropped surfaces — `totp/show`, `totp/confirm`,
      # `totp/disable`, `totp_backup_codes/*` — are gone. The
      # one-shot QR + codes render on `new`; finalization is `create`;
      # disable + backup-code rotation are operator-only.
      get  "totp", to: "totps#new",    as: :totp
      post "totp", to: "totps#create"
    end

    # Phase 26 — 01a. Timezone foundation. Singular `resource` so the
    # URL is `/settings/time_zone` (one stored zone per logged-in
    # user). PATCH from two callers — the Settings dropdown form and
    # the first-load Stimulus `timezone-detect` controller. Friendly
    # URL — no numeric / UUID id surface anywhere.
    resource :time_zone, only: %i[update], controller: "time_zone"

    # Beta 4 — F3-B. Unified notifications panel. Replaces the prior
    # per-brand `resource :slack_webhook` and `resource :discord_webhook`
    # endpoints. Two member-style actions on a single controller, one
    # per brand. The brand-specific URL form on the panel posts here:
    #
    #   PATCH /settings/notifications/discord -> `#update_discord`
    #   PATCH /settings/notifications/slack   -> `#update_slack`
    #
    # The tri-state contract (blank → no-op, "clear" → wipe, else →
    # validate + test-ping + save) is unchanged from the per-brand
    # controllers; only the URL path moved.
    patch "notifications/discord",
          to: "notifications#update_discord",
          as: :notifications_discord
    patch "notifications/slack",
          to: "notifications#update_slack",
          as: :notifications_slack

    # Phase 26 — 01d. Help-modal Markdown guides for the Slack +
    # Discord webhook panes. The `[help]` link in each pane targets
    # this endpoint via a Turbo Frame; the response is a fragment
    # rendered with `layout: false` and swapped into the layout-level
    # `<turbo-frame id="webhook_help_modal_frame">`. Friendly URL —
    # `/settings/webhooks/help/slack` and `/settings/webhooks/help/discord`
    # are the only two valid paths. The router constraint pins the
    # shape; the controller reapplies the allow-list as
    # defense-in-depth.
    namespace :webhooks do
      get "help/:provider",
          to: "help#show",
          as: :help,
          constraints: { provider: /slack|discord/ }
    end

    # Beta 4 — F3-B. Shared notification routing toggles. The unified
    # notifications panel renders ONE toggles block at the top; each
    # toggle flips the matching column on BOTH brand rows at once.
    # Two URL combinations only:
    #
    #   PATCH /settings/notification_toggles/all
    #   PATCH /settings/notification_toggles/daily_digest
    #
    # Form posts `enabled=yes|no` per the yes/no boundary rule. The
    # `:kind` segment is pinned by router constraint + re-checked in
    # the controller as defense-in-depth.
    patch "notification_toggles/:kind",
          to: "notification_toggles#update",
          as: :notification_toggle,
          constraints: { kind: /all|daily_digest/ }
  end

  # Phase 24 — Google management surface moved from `/settings/youtube`
  # onto `/channels` (banner on index + per-channel inline panel on
  # show + per-channel `[revoke]` flow). The legacy `/settings/youtube`
  # URL stays as a 301 redirect to `/channels` indefinitely — small
  # route, no maintenance cost, preserves browser bookmarks. The
  # request-phase `[connect]` entry point now lives at
  # `POST /channels/connect_google` (see the `:channels` resources
  # block above).
  get "/settings/youtube", to: redirect("/channels", status: 301)

  # 2026-05-25 (sync-rebuild) — the single mutation endpoint for the
  # server-side sync state. Replaces every `localStorage.setItem` call
  # the JS sync layer used to fire. `target=` query param carries the
  # dot-namespaced sync target (`app`, `home.<panel>`, or
  # `home.<panel>.<sub_panel>`); see `Pito::SyncTargets` for the
  # full universe.
  post "sync/toggle", to: "sync#toggle", as: :sync_toggle

  # 2026-05-25 (pause-from-sync) — explicit pause / resume endpoints.
  # Distinct from toggle: these pause without disabling sync entirely.
  # The `[-] sync` indicator reflects paused state; the user can resume
  # without losing the enabled/disabled preference.
  # `target=` follows the same dot-namespaced convention as `/sync/toggle`.
  # Routed to `SyncController#pause` / `SyncController#resume` (same
  # controller as the `/sync/toggle` action — no namespace module prefix).
  post "pito/sync/pause",  to: "sync#pause",  as: :pito_sync_pause
  post "pito/sync/resume", to: "sync#resume", as: :pito_sync_resume

  # 2026-05-25 — Pito::CalendarController navigation endpoints.
  #
  # Back the `Pito::Calendar::MonthGridComponent` Turbo Frame navigation
  # actions registered in `Pito::ActionRegistry` (see pito_actions.rb):
  #
  #   GET /pito/calendar/prev?month=YYYY-MM  → :calendar_prev_month
  #   GET /pito/calendar/next?month=YYYY-MM  → :calendar_next_month
  #   GET /pito/calendar/today               → :calendar_today
  #   GET /pito/calendar/pick_year           → :calendar_pick_year
  #
  # All four return a rendered `Pito::Calendar::MonthGridComponent`
  # inside the `#pito_calendar_panel` Turbo Frame.
  namespace :pito do
    scope :calendar do
      get "prev",            to: "calendar#prev",            as: :calendar_prev_month
      get "next",            to: "calendar#next",            as: :calendar_next_month
      get "today",           to: "calendar#today",           as: :calendar_today
      get "pick_year",       to: "calendar#pick_year",       as: :calendar_pick_year
      # Category filter — redirects to / with URL params so state lives in the URL (no localStorage).
      get "filter_category", to: "calendar#filter_category", as: :calendar_filter_category
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
