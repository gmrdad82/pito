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

  # Phase 12 — Step B (6b-doorkeeper-oauth-server.md). Doorkeeper mounts
  # `/oauth/authorize`, `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`.
  # We skip the bundled applications admin and replace it with our own UI
  # under `/settings/oauth_applications`.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end

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

  resources :channels, only: [ :index, :show, :edit, :update, :destroy ] do
    collection do
      get :panes
    end
    member do
      # Nested videos endpoint used by the pito CLI: /channels/:id/videos.json
      # returns the videos belonging to the channel as a JSON array.
      get :videos
      # Phase 7.5 §11i — open-diff resolution page. GET renders the
      # three-column reconciliation page; PATCH consumes the per-
      # field decisions form. JSON branch mirrors the
      # `channel_diff_show` / `channel_diff_apply` MCP tools.
      get   :diff
      patch :apply_diff
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
  resources :collections
  # Phase 14 §1 — IGDB-backed game model. `:search` (collection) is the
  # type-ahead endpoint that POSTs to IGDB for matches; `:resync` is
  # the per-game IGDB re-sync trigger. Existing CRUD remains.
  resources :games do
    collection do
      get :search
    end
    member do
      post :resync
    end
  end
  resources :footages, only: [ :index, :show, :edit, :update, :destroy ]

  # Phase 14 §2 — Bundles + composite covers. Full CRUD plus member
  # add/remove, plus a `seed_from_igdb` action that hydrates an
  # IGDB-source bundle from the IGDB API. Member URL shape is
  # `/bundles/:bundle_id/members/:id` where `:id` is the GAME id (not
  # the BundleMember id) per spec.
  resources :bundles do
    member do
      post :seed_from_igdb
    end
    resources :members, only: [ :create, :destroy ],
                        controller: "bundle_members"
  end

  # Phase 14 §2 — auth-gated composite cover serving. The `:filename`
  # route constraint pins the shape so path-traversal candidates
  # (`../etc/passwd`) never reach the controller (which reapplies the
  # regex as defense-in-depth).
  get "/composites/:filename.jpg",
      to: "composites#show",
      as: :composite_cover,
      constraints: { filename: /[a-z_]+-\d+/ },
      defaults: { format: "jpg" }

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
  patch "settings/theme", to: "settings#update_theme"
  post "settings/reindex", to: "settings#reindex"

  # Phase 3 — Step C (5c-settings-ui-and-docs.md). Token CRUD UI lives at
  # `/settings/tokens` so it has its own list / new / show flow without
  # cramming a 6th pane into the multi-section settings page. The
  # `/settings/tokens/:id/revoke` GET renders the action confirmation
  # screen (same UX pattern as `/deletions/:type/:ids`); the matching
  # DELETE soft-deletes by setting `revoked_at`.
  namespace :settings do
    # Phase 12 — user account self-service. The authenticated user can
    # change their own email or password. `current_password` is required
    # to authorize either mutation. No delete-account, no create-user,
    # no password-recovery flow (deferred). Singular `resource` so the
    # URL is `/settings/user` (not `/settings/users/:id`) — there is
    # only ever one "self" record per session. Pinned to the singular
    # `Settings::UserController` (Rails would otherwise pluralize a
    # singular `resource` to `Settings::UsersController`).
    resource :user, only: %i[show update], controller: "user"

    resources :tokens, only: %i[index new create destroy] do
      member do
        get :revoke
      end
    end

    # Phase 12 — Step A (6a-sessions-and-login-ui.md). Active Sessions
    # management mirrors the tokens shape: index, member revoke (action
    # screen), member destroy (the actual revoke).
    resources :sessions, only: %i[index destroy] do
      member do
        get :revoke
      end
    end

    # Phase 12 — Step B (6b-doorkeeper-oauth-server.md). OAuth
    # application admin. `:show` exposes the read-only detail; the
    # `create` action renders the show-secrets-once page rather than
    # redirecting (matching the `/settings/tokens` ceremony). The
    # `revoke` member route renders the action-screen confirmation
    # before the actual DELETE.
    resources :oauth_applications, only: %i[index new create show destroy] do
      member do
        get :revoke
      end
    end

    # Phase 7 — Step C (7c-settings-youtube-ui.md). Settings → YouTube
    # surface. `show` lists the connected Google accounts + every
    # Channel currently linked to those connections; `connect` is the
    # request-phase entry point for the OmniAuth dance (POST +
    # button_to from the show page; the `[add]` link passes
    # `account=new` to flip on `prompt=select_account`).
    #
    # The OAuth callback handles channel discovery — see
    # `YoutubeConnections::OauthCallbacksController#create`. The
    # legacy `POST /settings/youtube/channels` multi-select form is
    # gone; the bulk-disconnect path at `/deletions/youtube_connection/:ids`
    # is the only mutation surface this page wires directly.
    get  "/youtube",         to: "youtube#show",    as: :youtube
    post "/youtube/connect", to: "youtube#connect", as: :youtube_connect
  end

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
