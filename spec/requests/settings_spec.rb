require "rails_helper"

# Phase 29 (settings refactor) — `/settings` is a 3-row dashboard.
#
# Surfaces NOT covered here (each has its own request spec):
#   * `/settings/user`              — Settings::UserController#update
#   * `/settings/security/totp*`    — Settings::Security::TotpsController
#   * `/settings/sessions/revokes/:ids` — Settings::Sessions::BulkRevokesController
#   * `/settings/slack_webhook`     — Settings::SlackWebhooksController
#   * `/settings/discord_webhook`   — Settings::DiscordWebhooksController
#   * `/settings/time_zone`         — Settings::TimeZoneController
#   * `/settings/webhooks/help/*`   — Settings::Webhooks::HelpController
#
# 2026-05-16 (sessions revamp v2). The sessions table now renders
# INLINE in the Security pane on /settings; this spec carries the
# inline-table assertions below alongside the rest of the /settings
# coverage.
#
# Phase 32 follow-up (2026-05-16) — the OAuth applications + tokens
# management UI was dropped from /settings (operators now use
# `bin/rails pito:oauth_apps:*` / `bin/rails pito:tokens:*` rake
# tasks). The dropped routes have negative guards below; the
# Doorkeeper handshake routes stay live and are smoke-tested below.
#
# This spec covers /settings itself: index rendering, the legacy
# passthrough PATCH, the reindex endpoint, the JSON contract, and the
# dropped-surface negative guards.
RSpec.describe "Settings", type: :request do
  let(:search_engine) do
    instance_double(
      Search::MeilisearchEngine,
      healthy?: true,
      index_stats: {},
      per_index_stats: {}
    )
  end

  before do
    allow(Search).to receive(:engine).and_return(search_engine)
  end

  describe "GET /settings" do
    it "returns 200" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the page heading" do
      get settings_path
      expect(response.body).to include("<h1>settings</h1>")
    end

    describe "row 1 — profile + security" do
      it "renders the profile pane heading" do
        get settings_path
        expect(response.body).to include("<h2>profile</h2>")
      end

      it "renders the profile form posting to /settings/user" do
        get settings_path
        expect(response.body).to match(/action="\/settings\/user"/)
        expect(response.body).to include('name="user[username]"')
        expect(response.body).to include('name="user[current_password]"')
        expect(response.body).to include('name="user[password]"')
        expect(response.body).to include('name="user[password_confirmation]"')
      end

      it "renders the security pane heading" do
        get settings_path
        expect(response.body).to include("<h2>security</h2>")
      end

      # 2026-05-16 (sessions revamp v2). The three security launcher
      # links (`[ 2FA / TOTP ]`, `[ sessions ]`, `[ locations ]`) are
      # all gone:
      #   * `[ 2FA / TOTP ]` was dropped in the 2026-05-16 TOTP
      #     cleanup (manage page + disable flow moved to rake tasks).
      #   * `[ locations ]` was dropped post-Phase-25 along with the
      #     new-location approval surface.
      #   * `[ sessions ]` is now gone — the sessions table renders
      #     INLINE inside this pane.
      it "no longer renders any security launcher bracketed-link" do
        get settings_path
        expect(response.body).not_to include("2FA / TOTP")
        expect(response.body).not_to include('href="/settings/sessions"')
        expect(response.body).not_to include('href="/settings/security/blocks"')
      end

      # The settings modal dialog skeleton stays on the page — the
      # mandatory-2FA gate's auto-open path still uses it for TOTP
      # enrollment.
      it "renders the settings security modal dialog skeleton" do
        get settings_path
        expect(response.body).to include('id="settings_modal_frame"')
        expect(response.body).to include('data-controller="settings-modal"')
      end

      describe "inline sessions table in the Security pane (2026-05-16 revamp v2)" do
        it "renders the sessions-bulk-revoke Stimulus controller on the pane" do
          get settings_path
          expect(response.body).to include('data-controller="sessions-bulk-revoke"')
        end

        it "renders the idle bulk-revoke toolbar with `[revoke]`" do
          get settings_path
          expect(response.body).to include('data-sessions-bulk-revoke-target="link"')
          expect(response.body).to include("[revoke]")
        end

        it "renders the sessions table column headers (user-agent / pinged) — `ip` is no longer a column" do
          get settings_path
          expect(response.body).to include(">user-agent<")
          expect(response.body).to include(">pinged<")
        end

        it "does NOT render the dropped `ip` column header (the IP value now renders as an inline `[ip]` tooltip badge inside the user-agent cell)" do
          get settings_path
          # The dropped header was a sortable-header anchor (`<a
          # …>ip</a>`) emitted by `sort_link_to`. The inline `[ip]`
          # tooltip badge is a `<span>` (`StatusBadgeComponent`
          # primitive), so the negative guard targets the anchor
          # shape specifically.
          expect(response.body).not_to match(/<th[^>]*>\s*<a[^>]*>ip<\/a>\s*<\/th>/i)
          expect(response.body).not_to include("sessions_sort=ip")
        end

        it "does NOT render the dropped `active` or `remember` column headers" do
          get settings_path
          expect(response.body).not_to match(/<th[^>]*>\s*<a[^>]*>active<\/a>\s*<\/th>/i)
          expect(response.body).not_to match(/<th[^>]*>\s*<a[^>]*>remember<\/a>\s*<\/th>/i)
        end

        # 2026-05-16 (sessions revamp v2 polish). Inline trailing
        # badges replace the dropped `ip` column + the `(this
        # session)` muted text.
        #
        # Task #223 (2026-05-18) — the `[ip]` chip switched to the
        # filled-dark `:code` variant (white text on the dark muted-
        # badge surface, single color across both themes). The chip's
        # tooltip-host structure is unchanged.
        it "renders an inline `[ip]` tooltip badge for every session row" do
          get settings_path
          # The seeded user lands with at least the current session
          # row (authenticator-helper-driven). Each row carries an
          # `[ip]` tooltip-host badge with the `:code` variant.
          expect(response.body).to match(/class="status-badge status-badge--code tooltip-host"[^>]*data-tooltip="[^"]*"[^>]*>ip/)
        end

        it "renders a `[this]` neutral status badge for the current-session row instead of `(this session)` muted text" do
          get settings_path
          expect(response.body).to include(">this<")
          expect(response.body).not_to include("(this session)")
        end

        it "does NOT render the dropped helper copy block" do
          get settings_path
          expect(response.body).not_to include("active sessions open in a modal")
          expect(response.body).not_to include("the direct link still works for JS-off clients")
        end
      end

      describe "revoke-sessions confirm modal (2026-05-16 revamp v3)" do
        # The action-screen GET page is gone; the confirmation step is
        # now an in-page `<dialog>` mounted at the bottom of the
        # Security pane, populated client-side by the
        # `sessions-bulk-revoke` Stimulus controller.

        it "mounts the `revoke_sessions_modal` dialog at the pane level" do
          get settings_path
          expect(response.body).to include('id="revoke_sessions_modal"')
          # Same chrome controllers as the reindex modal — click-outside
          # + Escape close are handled by `confirm-modal`.
          expect(response.body).to match(/id="revoke_sessions_modal"[^>]*data-controller="confirm-modal"/)
        end

        it "exposes the modal targets the bulk-revoke controller needs (title / warning / form)" do
          get settings_path
          expect(response.body).to include('data-sessions-bulk-revoke-target="modal"')
          expect(response.body).to include('data-sessions-bulk-revoke-target="modalTitle"')
          expect(response.body).to include('data-sessions-bulk-revoke-target="modalWarning"')
          expect(response.body).to include('data-sessions-bulk-revoke-target="modalForm"')
        end

        it "renders the warning line hidden by default (Stimulus reveals it when current is in the set)" do
          get settings_path
          # `hidden` attribute on the warning div until JS flips it
          # based on `data-current="yes"` on the selected row.
          expect(response.body).to match(/data-sessions-bulk-revoke-target="modalWarning"[^>]*hidden/)
          # 2026-05-16 copy tweak — the two sentences render on
          # separate lines via two `<p>` tags (margin: 0 inline to
          # keep `.dialog-message`'s outer margin-bottom intact and
          # avoid the default user-agent paragraph gap between them).
          expect(response.body).to include("this set includes your current session.")
          expect(response.body).to include("revoking it signs you out.")
          # Structural proof of the two-paragraph layout — the first
          # `<p>` closes before the second one opens, sitting inside
          # the `modalWarning` container.
          expect(response.body).to match(
            %r{<p[^>]*>this set includes your current session\.</p>\s*<p[^>]*>revoking it signs you out\.</p>}
          )
        end

        it "bakes a session-bound CSRF token in the modal form (page-render context, not a broadcast)" do
          # `form_with`'s `token_tag` short-circuits to an empty string
          # whenever `protect_against_forgery?` returns false. The test
          # env runs with `allow_forgery_protection = false` for speed,
          # so we temporarily flip it on for this assertion — production
          # always has forgery protection on, which is what this spec is
          # really about.
          ActionController::Base.allow_forgery_protection = true
          begin
            get settings_path
            # The `form_with` inside the dialog renders an
            # `authenticity_token` hidden input — proof the token is
            # bound to the page's CSRF context. The placeholder ids
            # segment (`/revokes/0` — `0` satisfies the `[0-9,]+`
            # constraint, is dropped server-side by `parse_ids`) is
            # rewritten client-side, but the token must be present at
            # render time.
            expect(response.body).to match(/<form[^>]*action="\/settings\/sessions\/revokes\/0"/)
            expect(response.body).to match(/name="authenticity_token"[^>]*value="[^"]+"/)
            expect(response.body).to include('name="confirm" value="yes"')
          ensure
            ActionController::Base.allow_forgery_protection = false
          end
        end

        it "renders the `[revoke]` destructive button and the muted `[cancel]` close link" do
          get settings_path
          # 2026-05-16 copy tweak — button label dropped the redundant
          # `confirm ` prefix (the modal title already says
          # `revoke N session(s)?`). The bracketed label is rendered
          # as `[<span class="bl">revoke</span>]`, so the inner-text
          # match looks for `>revoke<` flanked by the span.
          expect(response.body).to include('<span class="bl">revoke</span>')
          expect(response.body).not_to include(">confirm revoke<")
          # Muted cancel link wired to `confirm-modal#close` (close
          # the dialog without submit).
          expect(response.body).to include("confirm-modal#close")
        end

        it "bakes `data-current=\"yes\"` on the current-session row checkbox so Stimulus can detect inclusion" do
          get settings_path
          # The seeded current session is the only `yes`; all other
          # rows would carry `no`. We assert at least one `yes`
          # appears alongside the checkbox target.
          expect(response.body).to match(/data-sessions-bulk-revoke-target="checkbox"[^>]*data-current="yes"|data-current="yes"[^>]*data-sessions-bulk-revoke-target="checkbox"/)
        end

        it "does NOT carry the old action-screen-page CSS markers (page is gone)" do
          get settings_path
          expect(response.body).not_to include("[confirm revoke]")
          # The action-screen page used `.action-screen-footer`
          # styling. The modal uses `.confirm-modal-actions
          # .modal-footer` instead — the action-screen marker should
          # NOT appear on `/settings`.
          expect(response.body).not_to include("action-screen-footer")
        end
      end
    end

    describe "row 2 — Discord + Slack webhook panes" do
      # Phase 32 follow-up (2026-05-16). The OAuth-applications +
      # tokens management surface moved out of /settings (to rake
      # tasks); row 2 is now two distinct webhook panes — Discord
      # LEFT, Slack RIGHT — instead of the prior stacked combined
      # pane.

      it "does NOT render the dropped OAuth applications heading" do
        get settings_path
        expect(response.body).not_to include("<h2>OAuth applications</h2>")
        expect(response.body).not_to include("new application")
      end

      it "does NOT render the dropped tokens heading" do
        get settings_path
        expect(response.body).not_to include("<h2>tokens</h2>")
        expect(response.body).not_to include("new token")
      end

      it "renders the Discord webhook form" do
        get settings_path
        expect(response.body).to include("<h2>Discord</h2>")
        expect(response.body).to include('name="discord_webhook_url"')
      end

      it "renders the Slack webhook form" do
        get settings_path
        expect(response.body).to include("<h2>Slack</h2>")
        expect(response.body).to include('name="slack_webhook_url"')
      end

      it "renders Discord and Slack as TWO separate .pane blocks (no hairline-stacking)" do
        get settings_path
        # Pull the contents of the row-2 pane-row by scanning between
        # the Discord <h2> and the row-3 stack pane. Two distinct
        # `<div class="pane">` openings indicate two side-by-side
        # panes rather than one stacked pane.
        body = response.body
        row2_start = body.index("<h2>Discord</h2>")
        row3_start = body.index("<h2>stack</h2>")
        expect(row2_start).not_to be_nil
        expect(row3_start).not_to be_nil
        expect(row2_start).to be < row3_start

        pane_openings = body[0...row3_start].scan(/<div class="pane">/).size
        # Row 1 right pane + the two row-2 panes (Discord + Slack) =
        # at least three `.pane` openings before row 3.
        expect(pane_openings).to be >= 3
      end
    end

    describe "dropped /settings/oauth_applications + /settings/tokens management UI (Phase 32 follow-up)" do
      # Rails returns 404 (not RoutingError) for unrouted GETs in
      # request specs because `ActionDispatch::DebugExceptions`
      # rescues `RoutingError` and renders the 404 page. Assert on
      # the response status to keep the contract durable across the
      # `config.consider_all_requests_local` boundary.
      it "returns 404 on GET /settings/oauth_applications" do
        get "/settings/oauth_applications"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on GET /settings/tokens" do
        get "/settings/tokens"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on GET /settings/oauth_applications/new" do
        get "/settings/oauth_applications/new"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on GET /settings/tokens/new" do
        get "/settings/tokens/new"
        expect(response).to have_http_status(:not_found)
      end

      it "the named route helpers for the dropped surfaces are no longer defined" do
        expect(Rails.application.routes.url_helpers).not_to respond_to(:settings_oauth_applications_path)
        expect(Rails.application.routes.url_helpers).not_to respond_to(:settings_tokens_path)
        expect(Rails.application.routes.url_helpers).not_to respond_to(:new_settings_token_path)
        expect(Rails.application.routes.url_helpers).not_to respond_to(:revoke_settings_token_path)
      end
    end

    describe "Doorkeeper handshake routes (kept)" do
      # The handshake routes still resolve — we only need to prove the
      # router did NOT return a 404. `/oauth/authorize` without params
      # / cookies yields a redirect to /login (anonymous) or to the
      # consent screen (authenticated); `/oauth/token` without a
      # grant returns a 400 / 401 from Doorkeeper. Anything but 404
      # is fine — that's the signal the routes are mounted.
      it "still routes GET /oauth/authorize (does not 404)" do
        get "/oauth/authorize"
        expect(response).not_to have_http_status(:not_found)
      end

      it "still routes POST /oauth/token (does not 404)" do
        post "/oauth/token"
        expect(response).not_to have_http_status(:not_found)
      end
    end

    describe "row 3 — stack pane" do
      it "renders the stack heading inside a wide pane" do
        get settings_path
        expect(response.body).to include("<h2>stack</h2>")
        expect(response.body).to include("pane--wide")
      end

      it "lists Postgres, Redis, Meilisearch, Voyage AI, assets, notes" do
        get settings_path
        # Task #236 / Phase 32 (2026-05-16) — the embeddings provider
        # label is `Voyage AI` everywhere in the UI; the older "Voyage
        # embeddings" wording was retired with the stack-pane surface
        # cut. Labels resolve via `t("settings.stack.*")` and
        # `t("settings.voyage.heading")` (`config/locales/settings/core.en.yml`).
        expect(response.body).to include("Postgres")
        expect(response.body).to include("Redis")
        expect(response.body).to include("Meilisearch")
        expect(response.body).to include("Voyage AI")
        expect(response.body).to include("assets")
        expect(response.body).to include("notes")
      end

      it "renders the reindex link wired to the confirm modal" do
        get settings_path
        expect(response.body).to include("reindex")
        expect(response.body).to include("reindex_meilisearch_modal")
      end

      # Phase 32 follow-up (2026-05-16) — reindex modal mount invariant.
      #
      # The `[reindex]` confirm modal is rendered at page level in
      # `_stack_pane.html.erb`, OUTSIDE the `<div id="voyage_section">`
      # broadcast target. `ReindexAllJob#broadcast_voyage_section` runs
      # in a job context with no `request` / `session`, so a `form_with`
      # nested inside the broadcast target would bake an
      # authenticity_token that is unbound to any user's session — the
      # next submit hits `InvalidAuthenticityToken`. Mounting the modal
      # at page-render time gives it a CSRF token bound to the current
      # session that stays valid across broadcast-driven state flips of
      # the trigger affordance. See the matching note in
      # `_voyage_section.html.erb`.
      describe "reindex modal mount (CSRF + broadcast safety)" do
        it "mounts the modal once on initial /settings GET" do
          get settings_path
          # `<dialog id="reindex_meilisearch_modal">` from
          # ConfirmModalComponent — a single match means we render the
          # modal exactly once and never accidentally also nest it
          # inside the broadcast target.
          expect(response.body.scan(/id="reindex_meilisearch_modal"/).count).to eq(1)
        end

        it "renders the modal OUTSIDE the <div id=\"voyage_section\"> " \
           "broadcast target" do
          get settings_path
          body = response.body

          voyage_open = body.index('id="voyage_section"')
          modal_open  = body.index('id="reindex_meilisearch_modal"')

          # Sanity: both anchors must exist in the rendered page.
          expect(voyage_open).not_to be_nil
          expect(modal_open).not_to  be_nil

          # Walk forward from `voyage_open` counting <div> opens and
          # </div> closes (the `voyage_section` div is the first
          # `<div>` that contains `id="voyage_section"`); the match
          # `</div>` that drops the depth back to zero is the
          # broadcast target's close. The modal must NOT live between
          # the open tag and that matching close.
          tail = body[voyage_open..]
          depth = 1
          cursor = tail.index(">", 0).to_i + 1  # advance past the open tag itself
          voyage_close_offset = nil
          loop do
            open_idx  = tail.index("<div",   cursor)
            close_idx = tail.index("</div>", cursor)
            break if close_idx.nil?
            if open_idx && open_idx < close_idx
              depth += 1
              cursor = open_idx + "<div".length
            else
              depth -= 1
              if depth.zero?
                voyage_close_offset = close_idx + voyage_open
                break
              end
              cursor = close_idx + "</div>".length
            end
          end
          expect(voyage_close_offset).not_to be_nil

          inside_broadcast_target = modal_open > voyage_open &&
                                    modal_open < voyage_close_offset
          expect(inside_broadcast_target).to eq(false),
            "Expected the reindex modal to be mounted OUTSIDE " \
            "`<div id=\"voyage_section\">` so the page-render CSRF " \
            "token survives broadcast-driven swaps of the trigger."
        end

        it "carries a session-bound CSRF token in the modal's form" do
          # `form_with`'s `token_tag` short-circuits to an empty string
          # whenever `protect_against_forgery?` returns false. The test
          # env runs with `allow_forgery_protection = false` for speed,
          # so we temporarily flip it on for this assertion — production
          # always has forgery protection on, which is what this spec is
          # really about.
          ActionController::Base.allow_forgery_protection = true
          begin
            get settings_path
            body = response.body

            # Slice the page-level modal's HTML and assert its
            # `authenticity_token` hidden input is present + non-empty.
            # The exact token value rotates per request — assert shape,
            # not value.
            modal_start = body.index('id="reindex_meilisearch_modal"')
            expect(modal_start).not_to be_nil

            # Look at a generous window after the modal open tag — the
            # ConfirmModalComponent form ships an `authenticity_token`
            # hidden input as the first form field.
            window = body[modal_start, 4_000].to_s
            expect(window).to match(/name="authenticity_token"\s+value="[^"]+"/)
          ensure
            ActionController::Base.allow_forgery_protection = false
          end
        end
      end
    end

    describe "dropped panes / fields (negative guards)" do
      it "drops the ui / ux pane" do
        get settings_path
        expect(response.body).not_to include("<h2>ui / ux</h2>")
        expect(response.body).not_to include('name="settings[theme]"')
        expect(response.body).not_to include('name="settings[keyboard_navigation_enabled]"')
      end

      it "drops the workspaces pane" do
        get settings_path
        expect(response.body).not_to include("<h2>workspaces</h2>")
        expect(response.body).not_to include('name="settings[max_panes]"')
        expect(response.body).not_to include('name="settings[pane_title_length]"')
      end

      it "drops the Voyage.ai pane" do
        get settings_path
        expect(response.body).not_to include("<h2>Voyage.ai</h2>")
        expect(response.body).not_to include('name="settings[voyage_index_project_notes]"')
      end

      it "drops the install-level time zone dropdown (only per-user via timezone-detect)" do
        get settings_path
        # The time zone pane lived inside the dropped workspaces row;
        # the per-user PATCH endpoint stays alive (timezone-detect
        # Stimulus controller writes to it).
        expect(response.body).not_to include("<h2>time zone</h2>")
      end

      it "drops the YouTube credentials pane" do
        get settings_path
        expect(response.body).not_to include("<h2>YouTube</h2>")
        expect(response.body).not_to include('name="settings[youtube_api_key]"')
      end
    end

    describe "JSON format" do
      it "returns 200" do
        get settings_path(format: :json)
        expect(response).to have_http_status(:ok)
      end

      it "returns the three workspace fields the CLI binds to" do
        get settings_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to include("max_panes", "pane_title_length", "theme")
      end

      it "returns integer values for max_panes + pane_title_length from config.x.pito" do
        get settings_path(format: :json)
        json = JSON.parse(response.body)
        expect(json["max_panes"]).to eq(Rails.application.config.x.pito.max_panes)
        expect(json["pane_title_length"]).to eq(Rails.application.config.x.pito.pane_title_length)
      end

      it "returns the static 'auto' theme placeholder" do
        get settings_path(format: :json)
        json = JSON.parse(response.body)
        expect(json["theme"]).to eq("auto")
      end
    end
  end

  describe "PATCH /settings (legacy passthrough)" do
    it "redirects to /settings with a notice (no 500s on dropped sections)" do
      patch settings_path, params: { section: "appearance", settings: { theme: "dark" } }
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(flash[:notice]).to eq("settings saved.")
    end

    it "redirects on the legacy voyage section without writing anything" do
      patch settings_path, params: { section: "voyage", settings: { voyage_index_project_notes: "yes" } }
      expect(response).to redirect_to(settings_path)
    end

    it "does not touch AppSetting rows on the legacy passthrough" do
      expect { patch settings_path, params: { section: "appearance", settings: { theme: "dark" } } }
        .not_to change { AppSetting.count }
    end
  end

  describe "POST /settings/reindex" do
    it "schedules ReindexAllJob and redirects" do
      expect(ReindexAllJob).to receive(:perform_later)
      post settings_reindex_path
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(flash[:notice]).to eq("reindex started.")
    end

    # Phase 32 follow-up (2026-05-16) — three-layer lock. The
    # controller is Layer 1: it consults `AppSetting.reindex_running?`
    # BEFORE enqueueing and short-circuits on a conflict.
    describe "with the DB flag already set (lock layer 1)" do
      it "redirects with an alert and does NOT enqueue a second job" do
        pending "validated manually first; spec fills in after the operator " \
                "confirms the controller short-circuits before perform_later"
        raise "pending placeholder"
      end
    end

    describe "with the DB flag clear" do
      it "flips the flag to running + stamps reindex_started_at before " \
         "enqueueing" do
        pending "validated manually first"
        raise "pending placeholder"
      end
    end
  end

  describe "PATCH /settings/theme (dropped)" do
    it "is not routable (404, no controller action)" do
      patch "/settings/theme", params: { theme: "dark" }
      # Rails routing falls through to a 404 since the route was
      # removed; the dropped action lives nowhere in `routes.rb`.
      expect(response.status).to eq(404).or eq(405)
    end
  end
end
