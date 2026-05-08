require "rails_helper"

# Phase 7 — Step A. Specs for the Google OAuth callback controller.
#
# Test strategy: OmniAuth's `test_mode = true` short-circuits the
# normal request → Google → callback chain. The `mock_auth[:google_oauth2]`
# hash is what OmniAuth places in `request.env["omniauth.auth"]`
# when the callback path is hit. The integration-test client then
# follows the chain via `follow_redirect!`.
#
# OmniAuth's request phase requires POST when `omniauth-rails_csrf_protection`
# is loaded. Test_mode + integration tests work fine with POST.
RSpec.describe "Auth::GoogleCallbacks", type: :request do
  before do
    OmniAuth.config.test_mode = true
    # Failure mode in test should not raise out of the rack chain.
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
      # Settings::YoutubeController#connect issues a 303 to
      # /auth/google_oauth2 (request phase).
      follow_redirect!
    else
      # Sign-in flow — go straight to the request phase.
      post "/auth/google_oauth2"
    end
    # The request phase in test_mode redirects to the callback.
    follow_redirect! if response.redirect?
  end

  describe "POST /auth/google_oauth2 → callback (test_mode)" do
    context "with the youtube_connect intent stashed" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = auth_hash }

      it "creates a GoogleIdentity and redirects to /settings/youtube" do
        expect {
          run_oauth_dance(intent: :youtube_connect)
        }.to change { GoogleIdentity.unscoped.count }.by(1)

        expect(response).to redirect_to(settings_youtube_path)
      end

      it "persists the access token, refresh token, and granted scopes" do
        run_oauth_dance(intent: :youtube_connect)
        identity = GoogleIdentity.unscoped.last
        expect(identity).not_to be_nil
        expect(identity.access_token).to eq("ya29.test-access-token")
        expect(identity.refresh_token).to eq("1//test-refresh-token")
        expect(identity.scopes).to include("openid", "email", "profile")
        expect(identity.last_authorized_at).to be_within(5.seconds).of(Time.current)
      end

      it "updates an existing GoogleIdentity on re-authorization" do
        existing = create(:google_identity,
                          google_subject_id: "1099876543210123456789",
                          email: "user@example.com",
                          access_token: "ya29.old-access",
                          refresh_token: "1//old-refresh")
        run_oauth_dance(intent: :youtube_connect)

        existing.reload
        expect(existing.access_token).to eq("ya29.test-access-token")
        expect(existing.refresh_token).to eq("1//test-refresh-token")
      end

      it "unions newly granted scopes into the existing scopes array" do
        existing = create(:google_identity,
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

      it "resets needs_reauth=false on a successful re-authorization" do
        create(:google_identity, :needs_reauth,
               google_subject_id: "1099876543210123456789",
               email: "user@example.com")

        run_oauth_dance(intent: :youtube_connect)

        expect(GoogleIdentity.unscoped.last.needs_reauth?).to be(false)
      end
    end

    context "with no intent stashed (sign-in flow placeholder)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = auth_hash }

      it "redirects to root_path (Phase 12 TODO placeholder)" do
        run_oauth_dance(intent: :sign_in)
        expect(response).to redirect_to(root_path)
      end

      it "does NOT create a GoogleIdentity in the sign-in branch (Phase 12 owns persistence)" do
        expect {
          run_oauth_dance(intent: :sign_in)
        }.not_to change { GoogleIdentity.unscoped.count }
      end
    end

    it "leaves a TODO marker pointing at Phase 12 in the controller source" do
      source = Rails.root.join("app/controllers/auth/google_callbacks_controller.rb").read
      expect(source).to match(/TODO\(phase-12\):/i)
    end

    context "on an OmniAuth failure (access_denied)" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
      end

      it "ends in /auth/failure with a non-200 response" do
        run_oauth_dance(intent: :sign_in)
        expect(response.body).to include("google sign-in failed")
      end
    end
  end

  describe "GET /auth/failure (direct hit)" do
    it "renders a non-200 response with the failure reason" do
      get google_oauth_failure_path, params: { message: "access_denied" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("google sign-in failed")
      expect(response.body).to include("access_denied")
    end
  end
end
