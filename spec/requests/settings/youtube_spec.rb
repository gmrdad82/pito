require "rails_helper"

# Settings → Google connection. The page lists every connected Google
# account (multi-connection support landed 2026-05-10) and, per
# connection, every Channel currently linked. The `[add]` button under
# each connection kicks the OAuth dance with `prompt=select_account`;
# the callback discovers `mine: true` channels and adds non-duplicates
# under the matching YoutubeConnection.
#
# The legacy "select channels to add" multi-select form is GONE — the
# `POST /settings/youtube/channels` route was dropped. Bulk-disconnect
# of channels routes through the existing
# `/deletions/youtube_connection/:ids` action-screen confirmation page
# (bulk-as-foundation: 1 or N comma-separated channel ids).
RSpec.describe "Settings::Youtube", type: :request do
  describe "GET /settings/youtube (manage page)" do
    context "with no YoutubeConnection" do
      it "renders the empty state with a connect button" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no Google account connected")
        expect(response.body).to include("[connect]")
      end

      it "renders the `Google connection` heading (singular, no connections)" do
        get settings_youtube_path
        expect(response.body).to include("<h1>Google connection</h1>")
        expect(response.body).not_to include("<h1>YouTube</h1>")
      end
    end

    context "with a YoutubeConnection in needs_reauth state" do
      before do
        @user = User.first
        @connection = create(:youtube_connection, :needs_reauth, user: @user,
                                                                 email: "u@example.test")
      end

      it "renders the red banner" do
        get settings_youtube_path
        expect(response.body).to include("your Google grant was revoked")
        expect(response.body).to include("[reconnect]")
      end

      # The settings/youtube show action no longer hits the YouTube API
      # (channel discovery moved to the OAuth callback). The original
      # `expect(Youtube::Client).not_to receive(:new)` guard stays
      # relevant — it now holds for every show render, not just
      # needs_reauth.
      it "does NOT call the YouTube API" do
        expect(Youtube::Client).not_to receive(:new)
        get settings_youtube_path
      end

      it "renders 200 even when the connection is in needs_reauth state" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("[reconnect]")
      end

      it "renders exactly one [reconnect] CTA (top banner only)" do
        get settings_youtube_path
        button_count = response.body.scan(/<button[^>]*type="submit"[^>]*>\[reconnect\]/).size
        expect(button_count).to eq(1)
      end

      it "does NOT leak the raw `needsreauth` error token in copy" do
        get settings_youtube_path
        expect(response.body).not_to include("needsreauth")
      end

      it "still renders the channels listing (it does not depend on the API)" do
        valid_url = "https://www.youtube.com/channel/UCyyyyyyyyyyyyyyyyyyyyyy"
        Channel.create!(channel_url: valid_url,
                        youtube_connection_id: @connection.id)

        get settings_youtube_path
        # Unified table — the slug rendered as the channel cell text
        # is enough; the legacy `channels` <h2> heading is gone.
        expect(response.body).to include("UCyyyyyyyyyyyyyyyyyyyyyy")
      end
    end

    # Phase 10 polish — copy differentiation. When `needs_reauth?` is
    # true AND the required `youtube.readonly` scope is missing from the
    # granted-scopes array, the banner reads "missing the scopes pito
    # needs" rather than the default "grant was revoked" message.
    context "with a YoutubeConnection in needs_reauth state missing required scopes" do
      before do
        @user = User.first
        @connection = create(:youtube_connection, :needs_reauth, user: @user,
                                                                 email: "u@example.test",
                                                                 scopes: %w[openid email profile])
      end

      it "renders the missing-scopes variant of the banner" do
        get settings_youtube_path
        expect(response.body).to include("missing the scopes pito needs")
        expect(response.body).to include("[reconnect]")
      end

      it "does NOT render the revoked-grant copy" do
        get settings_youtube_path
        expect(response.body).not_to include("your Google grant was revoked")
      end
    end

    context "with a fresh YoutubeConnection" do
      let(:user) { User.first }
      let!(:connection) do
        create(:youtube_connection, user: user, email: "u@example.test")
      end

      # The settings/youtube show no longer triggers a `mine: true`
      # YouTube API call — channel discovery moved to the OAuth
      # callback. The page is now a pure DB read.
      it "does NOT call the YouTube API on render" do
        expect(Youtube::Client).not_to receive(:new)
        get settings_youtube_path
      end

      it "does NOT render a [reconnect] button when the connection is healthy" do
        get settings_youtube_path
        expect(response.body).not_to include("[reconnect]")
      end

      # The unified-table redesign (2026-05-10) dropped the per-
      # connection metadata pane and the per-connection scopes <ul>.
      # Email, scopes, and linked-at all live inside the single table
      # below now.
      it "does NOT render the legacy per-connection metadata pane" do
        get settings_youtube_path
        expect(response.body).not_to match(/<div class="pane pane--wide"/)
        expect(response.body).not_to include("last authorized")
        expect(response.body).not_to include("last refreshed")
        expect(response.body).not_to match(/<th[^>]*>\s*scopes\s*<\/th>/)
      end

      describe "unified channels table" do
        it "renders the `select channels to add` heading nowhere" do
          get settings_youtube_path
          expect(response.body).not_to include("select channels to add")
          expect(response.body).not_to include("[<b>add channels</b>]")
          expect(response.body).not_to include("[add channels]")
        end

        it "does NOT render the legacy per-connection `[add]` button" do
          get settings_youtube_path
          expect(response.body).not_to match(
            /<button[^>]*type="submit"[^>]*>\[add\]<\/button>/
          )
        end

        it "renders a single `[+ add another Google account]` button below the table" do
          get settings_youtube_path
          expect(response.body).to include("[+ add another Google account]")
          add_count = response.body.scan(
            /<button[^>]*type="submit"[^>]*>\[\+ add another Google account\]<\/button>/
          ).size
          expect(add_count).to eq(1)
        end

        it "wires the `[+ add another Google account]` button at /settings/youtube/connect with account=new" do
          get settings_youtube_path
          expect(response.body).to match(
            /<form[^>]*action="#{Regexp.escape(settings_youtube_connect_path)}"[^>]*>[^<]*(?:<[^>]+>[^<]*)*?<input[^>]*name="account"[^>]*value="new"/m
          )
        end

        context "with no Channel rows linked to this connection" do
          it "renders the muted `no channels linked yet` note" do
            get settings_youtube_path
            expect(response.body).to include("no channels linked yet")
          end

          it "still renders the `[+ add another Google account]` button" do
            get settings_youtube_path
            expect(response.body).to include("[+ add another Google account]")
          end
        end

        context "with channels linked to this connection" do
          let!(:channel_a) do
            Channel.create!(
              channel_url: "https://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaaaa",
              youtube_connection_id: connection.id
            )
          end
          let!(:channel_b) do
            Channel.create!(
              channel_url: "https://www.youtube.com/channel/UCbbbbbbbbbbbbbbbbbbbbbb",
              youtube_connection_id: connection.id
            )
          end

          it "renders the four table headers: `channel`, `connected as`, `linked at`" do
            get settings_youtube_path
            expect(response.body).to match(/<th>\s*channel\s*<\/th>/)
            expect(response.body).to match(/<th>\s*connected as\s*<\/th>/)
            expect(response.body).to match(/<th>\s*linked at\s*<\/th>/)
          end

          it "renders a header checkbox (toggle-all) — the bulk-select pattern" do
            get settings_youtube_path
            expect(response.body).to match(
              /<input[^>]*type="checkbox"[^>]*data-bulk-select-target="headerCheckbox"/
            )
          end

          it "renders a per-row checkbox with the channel id as value" do
            get settings_youtube_path
            expect(response.body).to match(
              /<input[^>]*type="checkbox"[^>]*value="#{channel_a.id}"[^>]*data-bulk-select-target="checkbox"/
            )
            expect(response.body).to match(
              /<input[^>]*type="checkbox"[^>]*value="#{channel_b.id}"[^>]*data-bulk-select-target="checkbox"/
            )
          end

          it "renders each channel as a single flat <tr> row (no rowspan, no scopes row)" do
            get settings_youtube_path
            # Count <tr> rows inside <tbody> — two channels → exactly
            # two body rows, one per record. No second `<tr>` per
            # record carrying scopes.
            tbody = response.body[%r{<tbody>(.*?)</tbody>}m, 1] || ""
            tr_count = tbody.scan(/<tr\b/).size
            expect(tr_count).to eq(2)
          end

          it "does NOT render any `rowspan` attribute on the channel-row cells" do
            get settings_youtube_path
            tbody = response.body[%r{<tbody>(.*?)</tbody>}m, 1] || ""
            expect(tbody).not_to match(/rowspan=/)
          end

          it "does NOT render a `colspan` scopes row underneath the data row" do
            get settings_youtube_path
            expect(response.body).not_to match(
              /<td colspan="3"[^>]*class="scopes-line"/
            )
          end

          it "does NOT render the dropped period-separated short-label scopes line" do
            get settings_youtube_path
            expect(response.body).not_to match(
              /openid\.\s+email\.\s+profile\.\s+youtube\.readonly\.\s+yt-analytics\.readonly\.\s+youtube\.force-ssl\./
            )
          end

          it "does NOT render scopes as a bulleted <ul> list anymore" do
            get settings_youtube_path
            expect(response.body).not_to match(
              /<li[^>]*>\s*<code><strong>youtube\.readonly<\/strong><\/code>/
            )
          end

          it "renders checkbox + channel + connected-as + linked-at in each row" do
            channel_a.update_columns(created_at: 5.hours.ago)
            get settings_youtube_path
            tbody = response.body[%r{<tbody>(.*?)</tbody>}m, 1] || ""
            # Per-row checkbox (value=<channel.id>).
            expect(tbody).to match(
              /<input[^>]*type="checkbox"[^>]*value="#{channel_a.id}"/
            )
            # Channel slug derived from channel_url.
            expect(tbody).to include("UCaaaaaaaaaaaaaaaaaaaaaa")
            # Connected-as email.
            expect(tbody).to include("u@example.test")
            # Linked-at compact relative time.
            expect(tbody).to include("~5h ago")
          end

          it "does NOT render any per-row `[disconnect]` button" do
            get settings_youtube_path
            expect(response.body).not_to include("[disconnect]")
          end

          it "does NOT render a `state` column" do
            get settings_youtube_path
            expect(response.body).not_to match(/<th>\s*state\s*<\/th>/)
          end

          it "renders the connected-as email in the data row" do
            get settings_youtube_path
            expect(response.body).to include("u@example.test")
          end

          it "renders the relative-time `linked at` value via compact_time_ago" do
            channel_a.update_columns(created_at: 5.hours.ago)
            get settings_youtube_path
            expect(response.body).to include("~5h ago")
          end

          it "wraps the table in a bulk-select Stimulus controller with `youtube_connection` delete type" do
            get settings_youtube_path
            expect(response.body).to match(
              /data-controller="bulk-select"[^>]*data-bulk-select-delete-type-value="youtube_connection"/m
            )
          end

          it "labels the bulk delete action as `disconnect`" do
            # The Stimulus controller substitutes `deleteActionLabelValue`
            # into the rendered `[disconnect N]` button. The view must
            # set the override; "delete N" would surface the wrong verb.
            get settings_youtube_path
            expect(response.body).to match(
              /data-bulk-select-action-label-value="disconnect"/
            )
          end
        end
      end
    end

    # Brand accounts come back from Google with emails of the shape
    # `<long-id>@pages.plusgoogle.com`. The unified table truncates the
    # noisy domain so the connected-as cell shows just the local part.
    context "with a YoutubeConnection whose email is a brand-account address" do
      let(:user) { User.first }
      let!(:connection) do
        create(:youtube_connection,
               user: user,
               email: "witty-gaming-3646722185536190277@pages.plusgoogle.com")
      end
      let!(:channel) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCbrandbrandbrandbrandbb",
          youtube_connection_id: connection.id
        )
      end

      it "truncates @pages.plusgoogle.com from the rendered email" do
        get settings_youtube_path
        expect(response.body).to include("witty-gaming-3646722185536190277")
        expect(response.body).not_to include("pages.plusgoogle.com")
      end
    end

    context "with a YoutubeConnection whose email is a regular Gmail address" do
      let(:user) { User.first }
      let!(:connection) do
        create(:youtube_connection, user: user, email: "alice@gmail.com")
      end
      let!(:channel) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCgmailgmailgmailgmailgg",
          youtube_connection_id: connection.id
        )
      end

      it "renders the full email unchanged" do
        get settings_youtube_path
        expect(response.body).to include("alice@gmail.com")
      end
    end

    context "with multiple YoutubeConnections" do
      let(:user) { User.first }
      let!(:conn_a) do
        create(:youtube_connection, user: user, email: "a@example.test",
               last_authorized_at: 1.day.ago)
      end
      let!(:conn_b) do
        create(:youtube_connection, user: user, email: "b@example.test",
               last_authorized_at: 1.hour.ago)
      end
      let!(:channel_a) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCccccccccccccccccccccc1",
          youtube_connection_id: conn_a.id
        )
      end
      let!(:channel_b) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCccccccccccccccccccccc2",
          youtube_connection_id: conn_b.id
        )
      end

      it "renders the plural `Google connections` heading" do
        get settings_youtube_path
        expect(response.body).to include("<h1>Google connections</h1>")
      end

      it "renders both connections' emails inside the single unified table" do
        get settings_youtube_path
        expect(response.body).to include("a@example.test")
        expect(response.body).to include("b@example.test")
      end

      it "renders a SINGLE `[+ add another Google account]` button (no per-connection `[add]`)" do
        get settings_youtube_path
        # No `[add]` per connection any more.
        plain_add_count = response.body.scan(
          /<button[^>]*type="submit"[^>]*>\[add\]<\/button>/
        ).size
        expect(plain_add_count).to eq(0)

        plus_count = response.body.scan(
          /<button[^>]*type="submit"[^>]*>\[\+ add another Google account\]<\/button>/
        ).size
        expect(plus_count).to eq(1)
      end

      it "renders one unified channels <table> wrapping every channel across every connection" do
        get settings_youtube_path
        # The bulk-select controller wraps exactly one channels table.
        # Count the channel-row checkbox occurrences (one per
        # Channel, across both connections) — 2 channels total → 2
        # bulk-select-target="checkbox" inputs in a single bulk-select
        # tree.
        bulk_select_blocks = response.body.scan(
          /data-controller="bulk-select"[^>]*data-bulk-select-delete-type-value="youtube_connection"/m
        ).size
        expect(bulk_select_blocks).to eq(1)

        per_row_checkboxes = response.body.scan(
          /data-bulk-select-target="checkbox"/
        ).size
        expect(per_row_checkboxes).to eq(2)
      end
    end
  end

  describe "POST /settings/youtube/connect" do
    it "stashes the youtube_connection_oauth_intent and redirects to /auth/google_oauth2" do
      post settings_youtube_connect_path
      expect(response).to redirect_to("/auth/google_oauth2")
      expect(session[:youtube_connection_oauth_intent]).to eq("youtube_connect")
    end

    # `account=new` (the `[add]` and `[+ connect another Google account]`
    # buttons set this) flips the OAuth target to include
    # `prompt=select_account` so Google renders the account picker /
    # Brand-Account switcher instead of silently reusing the most-
    # recent grant.
    it "redirects with `prompt=select_account` when `account=new` is posted" do
      post settings_youtube_connect_path, params: { account: "new" }
      expect(response).to redirect_to(
        %r{/auth/google_oauth2\?prompt=select_account(%20|\+)consent&include_granted_scopes=true\z}
      )
      expect(session[:youtube_connection_oauth_intent]).to eq("youtube_connect")
    end

    it "still redirects to the plain auth URL without `account=new`" do
      post settings_youtube_connect_path
      expect(response).to redirect_to("/auth/google_oauth2")
    end
  end

  describe "POST /settings/youtube/channels (legacy multi-select submit — REMOVED)" do
    # The multi-select picker is gone — the route was removed entirely.
    # `url_helpers` no longer expose `settings_youtube_channels_path`.
    it "is no longer in url_helpers (route was dropped)" do
      expect(Rails.application.routes.url_helpers).not_to respond_to(:settings_youtube_channels_path)
    end
  end

  # Bulk-disconnect — the channels table on /settings/youtube wires its
  # `[disconnect N]` toolbar action at `/deletions/youtube_connection/:ids`.
  # The action screen and the destroy path already existed; these specs
  # cover the integration with the new UI shape (single id, multiple
  # ids, zero ids).
  describe "GET /deletions/youtube_connection/:ids (confirmation)" do
    it "renders the action-screen confirmation page for a single channel" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      get deletions_path(type: "youtube_connection", ids: channel.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disconnect")
      expect(response.body).to include("[confirm disconnect]")
    end

    it "renders the action-screen confirmation page for N channels (comma-joined ids)" do
      connection = create(:youtube_connection)
      a = create(:channel, youtube_connection: connection,
                 channel_url: "https://www.youtube.com/channel/UC11111111111111111111aa")
      b = create(:channel, youtube_connection: connection,
                 channel_url: "https://www.youtube.com/channel/UC22222222222222222222bb")

      get deletions_path(type: "youtube_connection", ids: [ a.id, b.id ].join(","))
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disconnect 2 YouTube channels")
      expect(response.body).to include("UC11111111111111111111aa")
      expect(response.body).to include("UC22222222222222222222bb")
    end

    it "redirects to /settings/youtube with an alert when there's nothing to disconnect" do
      # No matching ids — the action screen guards by redirecting
      # with a clean "nothing to disconnect" alert instead of
      # rendering an empty confirmation page.
      get deletions_path(type: "youtube_connection", ids: "99999")
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("nothing to disconnect")
    end
  end

  describe "DELETE /deletions/youtube_connection/:ids" do
    before { GoogleStubs.stub_revoke_success }

    it "clears youtube_connection_id, destroys the orphaned connection, redirects" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      delete youtube_connection_disconnect_path(ids: channel.id)

      expect(response).to redirect_to(settings_youtube_path)
      channel.reload
      expect(channel.youtube_connection_id).to be_nil
      expect(YoutubeConnection.unscoped.where(id: connection.id).exists?).to be(false)
    end

    it "disconnects multiple channels at once (bulk-as-foundation)" do
      connection = create(:youtube_connection)
      a = create(:channel, youtube_connection: connection,
                 channel_url: "https://www.youtube.com/channel/UC11111111111111111111aa")
      b = create(:channel, youtube_connection: connection,
                 channel_url: "https://www.youtube.com/channel/UC22222222222222222222bb")

      delete youtube_connection_disconnect_path(ids: [ a.id, b.id ].join(","))

      expect(response).to redirect_to(settings_youtube_path)
      a.reload
      b.reload
      expect(a.youtube_connection_id).to be_nil
      expect(b.youtube_connection_id).to be_nil
      expect(flash[:notice]).to include("disconnected 2 channels")
    end
  end
end
