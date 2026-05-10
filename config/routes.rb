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

  resources :channels, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    collection do
      get :panes
    end
    member do
      # Nested videos endpoint used by the pito CLI: /channels/:id/videos.json
      # returns the videos belonging to the channel as a JSON array.
      get :videos
    end
  end
  # Phase 12 — Path A2 retracted. Video gets back the writable subset
  # of YouTube Data API v3 fields plus the four-item pre-publish
  # checklist gating publish-state transitions. Edit / update fly the
  # writable subset; publish / schedule are dedicated paths so the
  # checklist gate cannot be bypassed.
  resources :videos, only: [ :index, :show, :edit, :update, :destroy ] do
    collection do
      get :panes
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
    end
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
  resources :notes, only: [ :index, :show, :update, :destroy ] do
    collection do
      # Phase 4 §6.4 — `[ scan now ]` enqueues NoteSyncJob.
      post :scan
    end
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

  resources :saved_views, only: [ :index, :create, :destroy ]

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

  # Phase 15 §2 — Calendar views. `/calendar` redirects to the current
  # month; canonical URLs are `/calendar/month/:year/:month` and
  # `/calendar/schedule`. Manual entries are CRUD'd under
  # `/calendar/entries`. The note endpoint allows derived/auto entries
  # to gain `metadata.user_overrides` notes (Open question #8 decision).
  get "/calendar",
      to: redirect { |_p, _req|
        now = Time.current
        "/calendar/month/#{now.year}/#{now.month}"
      },
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
    # surface. `show` lists the connected identity + the user's
    # YouTube channels; `connect` is the request-phase entry point
    # for the OmniAuth dance (POST + button_to from the show page);
    # `channels` connects a single channel into Pito's Channel table
    # by youtube_channel_id.
    get  "/youtube",          to: "youtube#show",     as: :youtube
    post "/youtube/connect",  to: "youtube#connect",  as: :youtube_connect
    post "/youtube/channels", to: "youtube#channels", as: :youtube_channels
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
