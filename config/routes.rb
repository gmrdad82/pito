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

  # Phase 7.5 — MCP OAuth discovery metadata. Two public, unauthenticated
  # JSON endpoints Claude.ai's MCP custom connector probes:
  #   - RFC 8414 — `/.well-known/oauth-authorization-server`
  #   - RFC 9728 — `/.well-known/oauth-protected-resource`
  # See `app/controllers/well_known_controller.rb`. Both are routed on
  # the same Rails app served by `app.pitomd.com` AND `mcp.pitomd.com`,
  # so a probe to either subdomain reaches the same controller. The
  # JSON `issuer` / `resource` values are hardcoded from
  # `Pito::PublicHosts`, NOT derived from `request.host`.
  get "/.well-known/oauth-authorization-server",
      to: "well_known#oauth_authorization_server",
      as: :oauth_authorization_server_metadata,
      defaults: { format: "json" }
  get "/.well-known/oauth-protected-resource",
      to: "well_known#oauth_protected_resource",
      as: :oauth_protected_resource_metadata,
      defaults: { format: "json" }
  # RFC 9728 §3.1 — per-resource metadata path mirrors the resource path.
  # Claude.ai's MCP connector probes `/.well-known/oauth-protected-resource/mcp`
  # after token exchange to verify the MCP resource is properly configured.
  # Returns the same metadata as the un-suffixed endpoint above.
  get "/.well-known/oauth-protected-resource/mcp",
      to: "well_known#oauth_protected_resource",
      as: :oauth_protected_resource_metadata_mcp,
      defaults: { format: "json" }

  # Phase 7.5 — MCP custom-connector icon discovery. Some clients
  # (and OS-level icon scrapers) ONLY check `/favicon.ico`. Pito ships
  # the brand mark as `public/Pito.png` and intentionally does NOT
  # carry a `.ico` binary in the repo — a 301 redirect to `/Pito.png`
  # is enough for clients that follow redirects, and the modern PNG
  # asset stays the single source of truth. `ActionDispatch::Static`
  # runs before the router, so this route only fires when no
  # `public/favicon.ico` file exists (which is the steady state).
  get "/favicon.ico", to: redirect("/Pito.png", status: 301)

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
  # Phase 12 — Path A2 retracted. Video gets back the writable subset
  # of YouTube Data API v3 fields plus the four-item pre-publish
  # checklist gating publish-state transitions. Edit / update fly the
  # writable subset; publish / schedule are dedicated paths so the
  # checklist gate cannot be bypassed.
  resources :videos, only: [ :index, :show, :edit, :update, :destroy ] do
    collection do
      get :panes
      # Phase 23 §23b — paginated index of every open VideoDiff
      # (per locked Q3). Click a row → opens the per-video diff page.
      get :diffs
    end
    member do
      # Nested stats endpoint used by the pito CLI: /videos/:id/stats.json
      # returns the per-day VideoStat rows for the video as a JSON array.
      get :stats
      # Phase 12 — pre-publish checklist gate + publish / schedule
      # actions. The GET renders a Turbo Frame partial; the PATCHes
      # are the actual privacy_status transition surface.
      get   :pre_publish_checklist
      patch :publish
      patch :schedule
      # Phase 12 — `public` / `unlisted` → `private` direct path.
      # Going down is free per Note 1 (no checklist needed). A
      # dedicated action keeps the privacy_status flip outside the
      # smuggle guard on `update`, which rejects any privacy_status
      # mutation through the regular update path.
      patch :unpublish
      # Phase 23 §23b + §23c — open-diff dialog. GET renders the
      # three-column reconciliation page; PATCH consumes the per-
      # field decisions form. JSON branch returns the same shape as
      # the `video_diff_show` / `video_diff_apply` MCP tools.
      get   :diff
      patch :apply_diff
    end
    # Phase 14 §3 — game / bundle attribution links nested under the
    # parent video. RESTful create / update / destroy; the bracketed
    # `[remove]` button on the edit form routes through the shared
    # `/deletions/video_game_link/:ids` action screen rather than
    # hitting `destroy` directly (no JS confirms — CLAUDE.md hard rule).
    resources :links, only: %i[create update destroy],
                      controller: "video_game_links"

    # Phase 13.3 — Per-video analytics dashboard. Singular `resource`
    # per master-agent decision. Two POST refresh endpoints:
    # `analytics/refresh` enqueues `VideoAnalyticsSync` (V1-V8 minus
    # V7), `analytics/retention/refresh` enqueues `VideoRetentionSync`
    # (V7) — separated so the retention curve (recomputed-in-place)
    # can be re-rolled independently.
    resource :analytics, only: :show, controller: "videos/analytics"
    post "analytics/refresh",
         to: "videos/analytics_refresh#create",
         as: :analytics_refresh
    post "analytics/retention/refresh",
         to: "videos/retention_refresh#create",
         as: :retention_refresh
  end
  # Phase 4 — Project Workspace. Phase A landed the route shells; Phase B
  # fills in the controller bodies and adds nested create routes for notes
  # and timelines (default-create lives on the parent project — §6.2/§11.1).
  resources :projects do
    resources :notes, only: [ :create ]
    resources :timelines, only: [ :create ]
  end
  # Phase 27 follow-up (2026-05-17) — `resources :collections` and the
  # `:games_pane` member action were removed along with the Collection
  # model. The `/games` page's former "collections shelf" is now a
  # "bundles shelf"; the modal-pane fragment route lives on `:bundles`
  # below (`get :games_pane`).
  # Phase 14 §1 — IGDB-backed game model. `:search` (collection) is the
  # type-ahead endpoint that POSTs to IGDB for matches; `:resync` is
  # the per-game IGDB re-sync trigger. Existing CRUD remains.
  resources :games, except: [ :edit, :update ] do
    collection do
      get :search
      # 2026-05-18 — omnisearch endpoint for the `/games` `/`-keyed
      # search modal (`:games_search` mode). Returns local games +
      # bundles (Meilisearch) AND IGDB hits as separate sections; the
      # caller renders `_search_results_combined`. Distinct from the
      # IGDB-only `:search` route above which still backs the
      # `:game_index` modal (`[+]` button on `/games` chrome).
      get :omnisearch
      # Phase 28 §01a — local primaries typeahead source for the
      # version-parent picker on the game edit page. Returns up to 20
      # `{ id, title }` JSON rows matching `LOWER(title) ILIKE` the
      # supplied `q` param. Primaries only (an edition cannot itself
      # parent another edition); the current row is excluded.
      get :version_parent_search
    end
    member do
      post :resync
    end
    # Phase 27 — 01f. Per-platform ownership editor. Singular
    # `resource` so the URL is `/games/:game_id/platform_ownerships/edit`
    # (one ownership editor per game). Routes friendly — `:game_id`
    # carries the slug because `Game#to_param` returns `igdb_slug`.
    resource :platform_ownerships, only: %i[edit update],
                                   module: :games

    # 2026-05-17 — inline per-platform ownership matrix toggles on
    # /games/:id. Each cell in the `OwnershipMatrixComponent` is a
    # checkbox inside a tiny auto-submit form. The form posts to one
    # of these two endpoints; the controller flips the join row (or
    # the singular `played_platform_id` pointer) and redirects back
    # to /games/:id with a flash naming the new state. Same posture
    # as the `/settings/notification_toggles/:brand/:kind` auto-save
    # endpoint (Phase D Discord/Slack toggles).
    #
    # `:platform` is the canonical slug — `ps`, `switch`, or `steam`
    # (per `Platforms::ChipComponent::SLUG_BRAND`). Anything else
    # 404s in the controller's allowlist check.
    patch "ownership_toggles/:platform",
          to: "games/ownership_toggles#ownership",
          as: :ownership_toggle
    patch "played_toggles/:platform",
          to: "games/ownership_toggles#played",
          as: :played_toggle
  end
  resources :footages, only: [ :index, :show, :edit, :update, :destroy ]

  # Phase 14 §2 / Phase 27 follow-up (2026-05-17 + 2026-05-18) — Bundles
  # + composite covers. The legacy `seed_from_igdb` action was removed
  # along with the IGDB-source provenance columns. The 2026-05-18
  # follow-up dropped the standalone `/bundles` index + `/bundles/new`
  # surfaces: bundles are reachable ONLY via the `/games` bundle shelf
  # + modal flow, so `index`, `new`, and `edit` actions are gone. What
  # remains:
  #   - show     : composite cover + member list (the modal links here
  #                for `[ open ]`).
  #   - create   : the `/games` bundles-shelf `[+]` button POSTs here.
  #                Builds an `unnamed bundle` (auto-incremented when a
  #                name collision exists) and renders a Turbo Stream
  #                that appends the new tile to the shelf, swaps the
  #                modal partial with auto-open wiring, and flashes a
  #                notice.
  #   - update   : modal inline-title-edit JSON PATCH (used by the
  #                `inline-title-edit` Stimulus controller from the
  #                `/games` bundles modal).
  #   - destroy  : routes through `/deletions/bundle/:ids` per the "no
  #                JS confirms" rule (called from `/games/:id`'s
  #                `[delete]`).
  #   - games_pane: Turbo Frame fragment that backs the `/games`
  #                bundles modal grid.
  # Members CRUD stays — used by the modal's add-member form.
  resources :bundles, only: [ :show, :create, :update, :destroy ] do
    member do
      get :games_pane
      # 2026-05-18 — omnisearch endpoint for the bundle modal's
      # `[+]` "add member" trigger (`:bundle_add` mode). Returns local
      # games (Meilisearch, with this bundle's existing members
      # filtered out) AND IGDB hits as separate sections; the result
      # row's `[add]` action POSTs `/bundles/:id/members` to associate
      # the chosen game with this bundle.
      get :search
    end
    resources :members, only: [ :create, :destroy ],
                        controller: "bundle_members"
  end

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
  # Phase B post-commit (2026-05-04) — Note revamp. The note editor is now
  # a single screen (no /edit) — `GET /notes/:id` renders the two-pane
  # editor directly. `/edit` and `/new` are intentionally absent.
  #
  # Phase 20 — friendly URLs. Notes resolve by their on-disk `path`
  # (which can include slashes when nested). Routes use a `*path` glob
  # so `/notes/projects/foo/bar.md` reaches the controller intact. Bulk
  # actions still go through `/deletions/note/:ids` (numeric ids).
  resources :notes, only: %i[index] do
    collection do
      # Phase 4 §6.4 — `[ scan now ]` enqueues NoteSyncJob.
      post :scan
    end
  end
  # Phase 20 — friendly URLs. `/*path` glob keeps slash-bearing
  # Note#path values intact (e.g. `subdir/file.md`). Setting
  # `format: false` prevents the `.md` suffix in the path from
  # being parsed as a Rails format token (which would 406 against
  # the controller's implicit HTML render); the controller's
  # `respond_to do |format|` block still honors the `Accept`
  # header so JSON request specs continue to receive JSON.
  scope :notes, as: :note do
    get    "/*path", to: "notes#show",    constraints: { path: /.+/ }, format: false
    patch  "/*path", to: "notes#update",  constraints: { path: /.+/ }, format: false
    put    "/*path", to: "notes#update",  constraints: { path: /.+/ }, format: false
    delete "/*path", to: "notes#destroy", constraints: { path: /.+/ }, format: false
  end
  resources :timelines, only: [ :index, :show, :update, :destroy ]

  # Importer download endpoint — single controller, branches on Rails.env
  # in Phase B. Route shell lands now (§14 step 8 ordering); controller body
  # is part of Phase B's CLI build/distribution workstream.
  get "footage/importer/download",
      to: "footage_importer/downloads#show",
      as: :footage_importer_download

  # Nested JSON API for the importer (Phase B). All four CRUD verbs live
  # under `/api/` for symmetry — collection actions on the project-nested
  # path, member actions on the flat `/api/footages/:id` path. The HTML
  # edit/destroy flow stays at the top-level `/footages/:id` (no .json).
  namespace :api do
    resources :projects, only: [] do
      resources :footages, only: [ :index, :create ]
    end
    resources :footages, only: [ :update, :destroy ] do
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
  get "/calendar",
      to: "calendar/router#show",
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
  get "settings", to: "settings#index"
  patch "settings", to: "settings#update"
  # Phase 29 (settings refactor) — `PATCH /settings/theme` removed.
  # Theme persistence moved to localStorage only; the Stimulus
  # `theme_controller` no longer hits the server.
  post "settings/reindex", to: "settings#reindex"

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
    # Phase 12 — user account self-service. The authenticated user can
    # change their own username or password. `current_password` is
    # required to authorize either mutation. No delete-account, no
    # create-user. Password recovery is the reset-via-2FA surface at
    # `/password/reset` (Phase 29 — Unit A2). Singular `resource` so the
    # URL is `/settings/user` (not `/settings/users/:id`) — there is
    # only ever one "self" record per session. Pinned to the singular
    # `Settings::UserController` (Rails would otherwise pluralize a
    # singular `resource` to `Settings::UsersController`).
    resource :user, only: %i[show update], controller: "user"

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

    # Phase 26 — 01b. Slack webhook pane. Singular `resource` so the
    # URL is `/settings/slack_webhook` — one Slack webhook config per
    # install (`notification_delivery_channels.kind = "slack"` row,
    # unique on `kind`). PATCH validates the URL regex, fires a test
    # ping, and only persists the row when the ping returns 2xx.
    resource :slack_webhook, only: %i[update], controller: "slack_webhooks"

    # Phase 26 — 01c. Discord webhook pane. Mirror of 01b for Discord.
    # URL: `/settings/discord_webhook` — one Discord webhook config per
    # install (`notification_delivery_channels.kind = "discord"` row,
    # unique on `kind`). PATCH validates the URL regex (accepts both
    # `discord.com` and `discordapp.com` host forms), fires a test
    # ping (`{ "content": ... }` — Discord requires the `content` key),
    # and only persists the row when the ping returns 2xx.
    resource :discord_webhook, only: %i[update], controller: "discord_webhooks"

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

    # 2026-05-17 — auto-save toggles for the 4 notification routing
    # flags (Discord every / Discord daily, Slack every / Slack daily).
    # One endpoint handles all four combinations; the `:brand` and
    # `:kind` segments are pinned by router constraints and reapplied
    # by the controller as defense-in-depth. The form posts
    # `enabled=yes|no` per the yes/no boundary rule. Phase C bindings
    # (`da`/`dd`/`sa`/`sd`) click the checkboxes via
    # `[data-leader-toggle]`; the change handler in `auto_submit`
    # Stimulus fires the PATCH and updates the flash region.
    patch "notification_toggles/:brand/:kind",
          to: "notification_toggles#update",
          as: :notification_toggle,
          constraints: { brand: /discord|slack/, kind: /everything|daily_digest/ }
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

  # MCP HTTP transport (served by dedicated Puma on port 3028).
  #
  # A single `Mcp::RackApp` instance is reused across mount points so
  # the in-memory transport state (session IDs etc.) is consistent
  # regardless of which path a client lands on. Two routes target it:
  #
  #   1. `POST /mcp` on any host — the canonical endpoint advertised
  #      in `/.well-known/oauth-protected-resource`'s `resource` field
  #      and pinned by `extras/cli/tests/`.
  #   2. `POST /` on `mcp.pitomd.com` — root-path alias for clients
  #      (Claude.ai's MCP custom connector being the motivating one)
  #      that POST directly to the connector URL the user typed,
  #      ignoring the metadata's `resource` value. Without this alias
  #      such clients get 404s. Constrained to the MCP host so the
  #      web app's `root "dashboard#index"` (GET /) is unaffected and
  #      `app.pitomd.com` does NOT leak the MCP endpoint at /.
  require_relative "../app/mcp/rack_app"
  mcp_rack_app = Mcp::RackApp.new
  mount mcp_rack_app => "/mcp"

  constraints host: "mcp.pitomd.com" do
    match "/", to: mcp_rack_app, via: :post, as: :mcp_root
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
