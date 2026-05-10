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
  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.failure_raise_out_environments = []
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
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
      extra: { raw_info: { scope: "openid email profile" } }
    )
  end

  # Hit the request phase, follow OmniAuth's internal redirect to
  # the callback path, and return after the controller has run.
  def run_oauth_dance(intent: :youtube_connect)
    if intent == :youtube_connect
      post settings_youtube_connect_path
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

        expect(response).to redirect_to(settings_youtube_path)
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

      it "unions newly granted scopes into the existing scopes array" do
        existing = create(:youtube_connection,
                          google_subject_id: "1099876543210123456789",
                          email: "user@example.com",
                          scopes: %w[openid email profile])
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(auth_hash.merge(
          extra: { raw_info: {
            scope: "openid email profile https://www.googleapis.com/auth/youtube.readonly"
          } }
        ))

        run_oauth_dance(intent: :youtube_connect)

        existing.reload
        expect(existing.scopes).to include(
          "openid", "email", "profile",
          "https://www.googleapis.com/auth/youtube.readonly"
        )
      end
    end

    context "with no intent stashed (stale-callback path)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = auth_hash }

      it "redirects to the failure path with the locked stale-intent flash copy" do
        run_oauth_dance(intent: :no_intent)
        expect(response).to redirect_to(youtube_connection_oauth_failure_path)
        expect(flash[:alert]).to eq(
          "sign-in via google is not supported. log in with email and password."
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

        expect(response.body).to include("google sign-in failed")
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

  describe "GET /auth/failure (direct hit)" do
    it "renders a non-200 response with the failure reason" do
      get youtube_connection_oauth_failure_path, params: { message: "access_denied" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("google sign-in failed")
      expect(response.body).to include("access_denied")
    end
  end
end
