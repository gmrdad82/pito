require "rails_helper"

# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Specs for the YouTube-connection OAuth callback.
#
# Test strategy: OmniAuth's `test_mode = true` short-circuits the
# normal request → Google → callback chain. The `mock_auth[:google_oauth2]`
# hash is what OmniAuth places in `request.env["omniauth.auth"]`
# when the callback path is hit. The integration-test client then
# follows the chain via `follow_redirect!`.
RSpec.describe "YoutubeConnections::OauthCallbacks", type: :request do
  # Sanity guard: the callback controller's `missing_required_scopes`
  # method references the bare top-level constant. The constant is
  # defined in `config/initializers/omniauth.rb`; if it ever drifts
  # (renamed, namespaced, deleted) the reconnect path raises NameError
  # in production. Lock the definition site and the contents here.
  describe "PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES constant" do
    it "is defined at the top level" do
      expect(defined?(PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES)).to eq("constant")
    end

    it "contains the three YouTube scope URLs pito needs" do
      expect(PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES).to contain_exactly(
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/yt-analytics.readonly",
        "https://www.googleapis.com/auth/youtube.force-ssl"
      )
    end

    it "is frozen so a runtime mutation can't drift the required set" do
      expect(PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES).to be_frozen
    end
  end

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.failure_raise_out_environments = []

    # The callback now enumerates `mine: true` channels under the
    # just-authorized connection (channel discovery moved out of the
    # /settings/youtube show action). Default the stub to an empty
    # response so existing specs that only care about the
    # `YoutubeConnection` upsert keep passing untouched; contexts
    # below that exercise discovery override this stub.
    allow_any_instance_of(Youtube::Client).to receive(:channels_list)
      .and_return(items: [], next_page_token: nil)
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  # Default mock hash returns the FULL pito scope set so the
  # partial-grant guard in the controller does NOT fire on these
  # baseline assertions. Sad-path tests below override `extra.raw_info.scope`
  # to simulate a user dismissing one or more scopes on the consent
  # screen.
  let(:full_granted_scope_string) do
    [
      "openid", "email", "profile",
      "https://www.googleapis.com/auth/youtube.readonly",
      "https://www.googleapis.com/auth/yt-analytics.readonly",
      "https://www.googleapis.com/auth/youtube.force-ssl"
    ].join(" ")
  end

  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "1099876543210123456789",
      info: { email: "user@example.com", name: "Sample User" },
      credentials: {
        token: "ya29.test-access-token",
        refresh_token: "1//test-refresh-token",
        expires_at: 1.hour.from_now.to_i
      },
      extra: { raw_info: { scope: full_granted_scope_string } }
    )
  end

  # Hit the request phase, follow OmniAuth's internal redirect to
  # the callback path, and return after the controller has run.
  def run_oauth_dance(intent: :youtube_connect)
    if intent == :youtube_connect
      post connect_google_channels_path
      follow_redirect!
    else
      # No-intent flow — go straight to the request phase; the callback
      # treats the missing session intent as stale.
      post "/auth/google_oauth2"
    end
    follow_redirect! if response.redirect?
  end

  describe "POST /auth/google_oauth2 → callback (test_mode)" do
    context "with the youtube_connect intent stashed" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = auth_hash }

      it "creates a YoutubeConnection and redirects to /settings/youtube" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { YoutubeConnection.unscoped.count }.by(1)

        expect(response).to redirect_to(channels_path)
      end

      it "persists the access token, refresh token, and granted scopes (encrypted columns hold ciphertext)" do
        run_oauth_dance(intent: :youtube_connect)
        connection = YoutubeConnection.unscoped.last
        expect(connection).not_to be_nil
        expect(connection.access_token).to eq("ya29.test-access-token")
        expect(connection.refresh_token).to eq("1//test-refresh-token")
        expect(connection.scopes).to include("openid", "email", "profile")
        expect(connection.last_authorized_at).to be_within(5.seconds).of(Time.current)

        # The on-disk column carries ciphertext, not the plaintext value.
        raw = connection.read_attribute_before_type_cast(:access_token)
        expect(raw).not_to include("ya29.test-access-token")
      end

      it "persists every YouTube scope the consent screen returned (full pito scope set)" do
        run_oauth_dance(intent: :youtube_connect)
        connection = YoutubeConnection.unscoped.last
        expect(connection.scopes).to include(
          "https://www.googleapis.com/auth/youtube.readonly",
          "https://www.googleapis.com/auth/yt-analytics.readonly",
          "https://www.googleapis.com/auth/youtube.force-ssl"
        )
      end

      it "leaves needs_reauth false when the grant covers every required scope" do
        run_oauth_dance(intent: :youtube_connect)
        connection = YoutubeConnection.unscoped.last
        expect(connection.needs_reauth?).to be(false)
      end

      it "refreshes the existing connection on re-authorization (NO new row)" do
        existing = create(:youtube_connection,
                          google_subject_id: "1099876543210123456789",
                          email: "user@example.com",
                          access_token: "ya29.old-access",
                          refresh_token: "1//old-refresh",
                          needs_reauth: true)

        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.not_to change { YoutubeConnection.unscoped.count }

        existing.reload
        expect(existing.access_token).to eq("ya29.test-access-token")
        expect(existing.refresh_token).to eq("1//test-refresh-token")
        expect(existing.needs_reauth?).to be(false)
        expect(existing.last_authorized_at).to be_within(5.seconds).of(Time.current)
      end

      it "creates a SECOND row when a different Google account connects" do
        user = User.first
        create(:youtube_connection,
               user: user,
               google_subject_id: "first-subject-9999999999999",
               email: "first@example.com")

        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { YoutubeConnection.unscoped.where(user_id: user.id).count }.by(1)

        expect(YoutubeConnection.unscoped.where(user_id: user.id).count).to eq(2)
      end

      # Multi-connection (2026-05-10). The earlier row's tokens MUST
      # stay intact when a second Google account connects — the
      # callback finds-or-initializes keyed on `google_subject_id`, so
      # a different subject creates a new row alongside, never
      # mutating the existing one.
      it "leaves the FIRST connection's tokens untouched when a SECOND account connects" do
        user = User.first
        first = create(:youtube_connection,
                       user: user,
                       google_subject_id: "first-subject-9999999999999",
                       email: "first@example.com",
                       access_token: "ya29.first-access-token-xxxxxxxx",
                       refresh_token: "1//first-refresh-token-xxxxxxxx",
                       last_authorized_at: 1.day.ago)
        original_access = first.access_token
        original_refresh = first.refresh_token
        original_authorized_at = first.last_authorized_at

        run_oauth_dance(intent: :youtube_connect)

        first.reload
        expect(first.access_token).to eq(original_access)
        expect(first.refresh_token).to eq(original_refresh)
        expect(first.last_authorized_at.to_i).to eq(original_authorized_at.to_i)

        # The second row carries the auth_hash's subject id.
        second = YoutubeConnection.unscoped.find_by(google_subject_id: "1099876543210123456789")
        expect(second).not_to be_nil
        expect(second.id).not_to eq(first.id)
        expect(second.access_token).to eq("ya29.test-access-token")
      end

      it "replaces the stored scopes with the current grant (no stale union)" do
        # Approach B (config/initializers/omniauth.rb scope-strategy
        # block): every authorization round returns the full scope set,
        # so the stored array reflects the current token's grant — not
        # a historical union. A previous narrow scope set must NOT
        # mask a present-day missing scope.
        existing = create(:youtube_connection,
                          google_subject_id: "1099876543210123456789",
                          email: "user@example.com",
                          scopes: %w[
                            openid email profile
                            https://www.googleapis.com/auth/youtube.readonly
                            https://www.googleapis.com/auth/yt-analytics.readonly
                            https://www.googleapis.com/auth/youtube.force-ssl
                            https://www.googleapis.com/auth/legacy-scope-from-history
                          ])
        # Callback returns only the current (full) scope set — the
        # legacy "history" scope is NOT in the new grant.
        run_oauth_dance(intent: :youtube_connect)

        existing.reload
        expect(existing.scopes).to include(
          "openid", "email", "profile",
          "https://www.googleapis.com/auth/youtube.readonly",
          "https://www.googleapis.com/auth/yt-analytics.readonly",
          "https://www.googleapis.com/auth/youtube.force-ssl"
        )
        expect(existing.scopes).not_to include(
          "https://www.googleapis.com/auth/legacy-scope-from-history"
        )
      end
    end

    context "with the youtube_connect intent stashed and a PARTIAL scope grant" do
      # Google's consent screen lets the user uncheck individual
      # scopes. The callback hash still says "success" but the token
      # is missing one or more scopes pito needs.
      let(:partial_auth_hash) do
        OmniAuth::AuthHash.new(
          provider: "google_oauth2",
          uid: "1099876543210123456789",
          info: { email: "user@example.com", name: "Sample User" },
          credentials: {
            token: "ya29.test-access-token",
            refresh_token: "1//test-refresh-token",
            expires_at: 1.hour.from_now.to_i
          },
          extra: { raw_info: {
            # User unchecked youtube.force-ssl on the consent screen.
            scope: "openid email profile " \
                   "https://www.googleapis.com/auth/youtube.readonly " \
                   "https://www.googleapis.com/auth/yt-analytics.readonly"
          } }
        )
      end

      before { OmniAuth.config.mock_auth[:google_oauth2] = partial_auth_hash }

      it "still creates the YoutubeConnection row" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { YoutubeConnection.unscoped.count }.by(1)
      end

      it "flips needs_reauth back to true so the manage page shows the missing-scopes banner" do
        run_oauth_dance(intent: :youtube_connect)
        connection = YoutubeConnection.unscoped.last
        expect(connection.needs_reauth?).to be(true)
      end

      it "stores ONLY the partially granted scopes (no force-ssl)" do
        run_oauth_dance(intent: :youtube_connect)
        connection = YoutubeConnection.unscoped.last
        expect(connection.scopes).to include(
          "https://www.googleapis.com/auth/youtube.readonly",
          "https://www.googleapis.com/auth/yt-analytics.readonly"
        )
        expect(connection.scopes).not_to include(
          "https://www.googleapis.com/auth/youtube.force-ssl"
        )
      end

      it "redirects back to /settings/youtube with the partial-grant flash" do
        run_oauth_dance(intent: :youtube_connect)
        expect(response).to redirect_to(channels_path)
        expect(flash[:alert]).to eq(
          YoutubeConnections::OauthCallbacksController::PARTIAL_GRANT_FLASH
        )
      end

      it "does NOT leave the success flash in place" do
        run_oauth_dance(intent: :youtube_connect)
        expect(flash[:notice]).to be_blank
      end
    end

    context "with no intent stashed (stale-callback path)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = auth_hash }

      it "redirects to the failure path with the locked stale-intent flash copy" do
        run_oauth_dance(intent: :no_intent)
        expect(response).to redirect_to(youtube_connection_oauth_failure_path)
        # Reference the constant directly so the brand-casing
        # sweep (lowercase → capital `Google`) doesn't double-touch
        # the spec.
        expect(flash[:alert]).to eq(
          YoutubeConnections::OauthCallbacksController::STALE_INTENT_FLASH
        )
      end

      it "does NOT create a YoutubeConnection" do
        expect {
          run_oauth_dance(intent: :no_intent)
        }.not_to change { YoutubeConnection.unscoped.count }
      end
    end

    context "on an OmniAuth failure (access_denied)" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
      end

      it "ends in /auth/failure with a non-200 response and creates no row" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.not_to change { YoutubeConnection.unscoped.count }

        expect(response.body).to match(/[gG]oogle sign-in failed/)
      end
    end

    context "with no Current.user in scope" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = auth_hash
        # Force the controller's Current.user to be nil even though the
        # request would otherwise come from a logged-in dev session.
        # The controller branches on `Current.user.present?` inside
        # `upsert_youtube_connection_for_current_user`.
        allow(Current).to receive(:user).and_return(nil)
      end

      it "redirects to the failure path and creates no row" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.not_to change { YoutubeConnection.unscoped.count }

        expect(response).to redirect_to(youtube_connection_oauth_failure_path)
        expect(flash[:alert]).to include("session expired")
      end
    end
  end

  # Channel discovery on a successful callback (2026-05-10 redesign).
  # The OAuth callback enumerates `mine: true` channels under the
  # just-authorized connection and adds non-duplicates as Channel rows.
  # Duplicates (UC id already in the Channel table) are silently
  # skipped; the flash carries an "already linked" note. API failures
  # (quota, transient, needs reauth) surface in flash but do NOT
  # prevent the OAuth-success redirect.
  describe "POST /auth/google_oauth2 → callback → channel discovery" do
    before { OmniAuth.config.mock_auth[:google_oauth2] = auth_hash }

    context "when the granted access returns two new channels" do
      before do
        allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
          items: [
            { id: "UCnnnnnnnnnnnnnnnnnnnnnn",
              snippet: { title: "New Alpha" },
              statistics: { subscriber_count: 12 } },
            { id: "UCmmmmmmmmmmmmmmmmmmmmmm",
              snippet: { title: "New Beta" },
              statistics: { subscriber_count: 34 } }
          ],
          next_page_token: nil
        )
      end

      it "creates a Channel row per non-duplicate" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { Channel.count }.by(2)

        connection = YoutubeConnection.unscoped.last
        expect(connection.channels.map(&:channel_url)).to contain_exactly(
          "https://www.youtube.com/channel/UCnnnnnnnnnnnnnnnnnnnnnn",
          "https://www.youtube.com/channel/UCmmmmmmmmmmmmmmmmmmmmmm"
        )
      end

      it "redirects to /settings/youtube with a flash naming the added channels" do
        run_oauth_dance(intent: :youtube_connect)
        expect(response).to redirect_to(channels_path)
        expect(flash[:notice]).to include("Google account connected.")
        expect(flash[:notice]).to include("2 channels added")
        expect(flash[:notice]).to include("New Alpha")
        expect(flash[:notice]).to include("New Beta")
      end
    end

    context "when one of the returned channels is already linked to pito (DUPLICATE edge case)" do
      let!(:existing_channel) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCdupdupdupdupdupdupdupx",
          last_synced_at: 1.day.ago
        )
      end

      before do
        allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
          items: [
            # A duplicate (already in pito) — must be silently
            # skipped, no crash, no second row.
            { id: "UCdupdupdupdupdupdupdupx",
              snippet: { title: "Already Linked" },
              statistics: { subscriber_count: 7 } },
            # A brand-new channel — must be linked under the new
            # connection alongside the silent-skip above.
            { id: "UCfreshfreshfreshfreshfx",
              snippet: { title: "Fresh New" },
              statistics: { subscriber_count: 9 } }
          ],
          next_page_token: nil
        )
      end

      it "does NOT crash" do
        expect { run_oauth_dance(intent: :youtube_connect) }.not_to raise_error
      end

      it "does NOT create a second Channel row for the duplicate UC id" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { Channel.count }.by(1)
        # Exactly one channel exists for the duplicate UC id.
        dupes = Channel.where(channel_url: "https://www.youtube.com/channel/UCdupdupdupdupdupdupdupx")
        expect(dupes.count).to eq(1)
      end

      it "adds the brand-new channel alongside (silent skip on the duplicate)" do
        run_oauth_dance(intent: :youtube_connect)
        connection = YoutubeConnection.unscoped.last
        expect(connection.channels.map(&:channel_url)).to contain_exactly(
          "https://www.youtube.com/channel/UCfreshfreshfreshfreshfx"
        )
      end

      it "flashes a clean 'already linked' note (no error tone)" do
        run_oauth_dance(intent: :youtube_connect)
        expect(flash[:notice]).to include("Google account connected.")
        expect(flash[:notice]).to include("1 channel added")
        expect(flash[:notice]).to include("Fresh New")
        # The duplicate handling: a single duplicate uses the singular
        # "channel '<title>' is already linked." copy.
        expect(flash[:notice]).to include("channel 'Already Linked' is already linked")
        expect(flash[:alert]).to be_blank
      end

      it "leaves the duplicate's existing youtube_connection_id alone" do
        # The duplicate already had a connection (the factory-created
        # one) — re-attaching it to the new connection would be a
        # silent steal. The duplicate path is silent-skip; the
        # existing row is untouched.
        existing_channel.update_columns(youtube_connection_id: nil)
        run_oauth_dance(intent: :youtube_connect)
        existing_channel.reload
        expect(existing_channel.youtube_connection_id).to be_nil
      end
    end

    context "when EVERY returned channel is already linked" do
      let!(:dupe_a) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCdup1dup1dup1dup1dup1dx",
          last_synced_at: 1.day.ago
        )
      end
      let!(:dupe_b) do
        Channel.create!(
          channel_url: "https://www.youtube.com/channel/UCdup2dup2dup2dup2dup2dx",
          last_synced_at: 1.day.ago
        )
      end

      before do
        allow_any_instance_of(Youtube::Client).to receive(:channels_list).and_return(
          items: [
            { id: "UCdup1dup1dup1dup1dup1dx",
              snippet: { title: "Dupe A" } },
            { id: "UCdup2dup2dup2dup2dup2dx",
              snippet: { title: "Dupe B" } }
          ],
          next_page_token: nil
        )
      end

      it "creates no new Channel rows" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.not_to change { Channel.count }
      end

      it "flashes the plural 'these channels are already linked' note" do
        run_oauth_dance(intent: :youtube_connect)
        expect(flash[:notice]).to include("these channels are already linked: Dupe A, Dupe B")
      end
    end

    context "when the YouTube API raises QuotaExhaustedError" do
      before do
        allow_any_instance_of(Youtube::Client).to receive(:channels_list)
          .and_raise(Youtube::QuotaExhaustedError)
      end

      it "still completes the redirect (no 500)" do
        run_oauth_dance(intent: :youtube_connect)
        expect(response).to redirect_to(channels_path)
      end

      it "creates no Channel rows" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.not_to change { Channel.count }
      end

      it "still creates the YoutubeConnection" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { YoutubeConnection.unscoped.count }.by(1)
      end

      it "flashes a human-readable note explaining the retry path" do
        run_oauth_dance(intent: :youtube_connect)
        expect(flash[:notice]).to include("Google account connected.")
        expect(flash[:notice]).to include("quota exceeded")
        expect(flash[:notice]).to include("click [+] to retry")
      end
    end

    context "when the YouTube API returns no channels under this account" do
      before do
        allow_any_instance_of(Youtube::Client).to receive(:channels_list)
          .and_return(items: [], next_page_token: nil)
      end

      it "creates no Channel rows" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.not_to change { Channel.count }
      end

      it "flashes the 'no channels found' note" do
        run_oauth_dance(intent: :youtube_connect)
        expect(flash[:notice]).to include("no channels found under this Google account")
      end
    end
  end

  describe "GET /auth/failure (direct hit)" do
    it "renders a non-200 response with the failure reason" do
      get youtube_connection_oauth_failure_path, params: { message: "access_denied" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("Google sign-in failed")
      expect(response.body).to include("access_denied")
    end
  end
end
