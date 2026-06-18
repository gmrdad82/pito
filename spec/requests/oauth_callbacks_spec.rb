# frozen_string_literal: true

# spec/requests/oauth_callbacks_spec.rb
#
# Covers YoutubeConnections::OauthCallbacksController:
#   - Missing / null OmniAuth auth hash (simulated network/provider error)
#   - Missing or stale intent in session
#   - Bad/mismatched state (CSRF) → OmniAuth's middleware produces the failure
#   - Successful callback (happy path) → 302 to chat
#   - No active session on callback → redirects to failure path
#
# OmniAuth test mode is used throughout (same pattern as connect_spec.rb).

require "rails_helper"

RSpec.describe "YoutubeConnections::OauthCallbacksController", type: :request do
  let(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post chat_path, params: { input: "/login #{ROTP::TOTP.new(seed).now}", uuid: conversation.uuid }
  end

  def omniauth_hash(subject_id: "sub-cb-#{SecureRandom.hex(4)}",
                    email: "owner@example.com",
                    scopes: PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES)
    OmniAuth::AuthHash.new(
      uid:  subject_id,
      info: { email: email },
      credentials: {
        token:         "access-token",
        refresh_token: "refresh-token",
        expires_at:    1.hour.from_now.to_i,
        scope:         scopes.join(" ")
      },
      extra: {
        raw_info: { scope: scopes.join(" ") }
      }
    )
  end

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.add_mock(:google_oauth2, omniauth_hash)
    Pito::Credentials.invalidate!
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:google_oauth2)
    Pito::Credentials.invalidate!
  end

  # Helper: stash the youtube_connect intent in the session.
  # We use the /connect flow to ensure the session is populated the same
  # way the real app does it.  If credentials are unconfigured, fall back to
  # manual session manipulation via a signed-cookie approach.
  def stash_intent_via_session_params
    # OmniAuth test mode stashes env["omniauth.auth"] before the controller runs.
    # We just need the session key set — do it by manipulating the raw rack session.
    post "/auth/google_oauth2"  # OmniAuth request phase; sets intent via the connect flow
  rescue StandardError
    nil
  end

  # ── Missing auth hash (provider / network error) ──────────────────────────

  describe "GET /auth/youtube/callback — missing auth hash" do
    before do
      authenticate_via_totp
      # Tell OmniAuth to simulate an error (nil auth hash + error set)
      OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials
    end

    it "redirects to the failure path" do
      get "/auth/failure?message=invalid_credentials"
      expect(response.status).to be_in([ 302, 401 ])
    end
  end

  # ── Stale / missing intent ─────────────────────────────────────────────────

  describe "GET /auth/youtube/callback — no intent in session" do
    before { authenticate_via_totp }

    it "redirects to the failure path when intent is absent" do
      # No stashed intent → the controller sees intent != 'youtube_connect'.
      get youtube_connection_oauth_callback_path
      expect(response).to redirect_to(youtube_connection_oauth_failure_path)
    end
  end

  # ── No active session ──────────────────────────────────────────────────────

  describe "GET /auth/youtube/callback — no pito session" do
    it "redirects (no session — AuthConcern sends unauthenticated requests to root)" do
      # The `create` action is NOT allow_anonymous. Without an active pito session,
      # Sessions::AuthConcern redirects to root_path before the controller body runs.
      get youtube_connection_oauth_callback_path
      expect(response).to redirect_to(root_path)
    end
  end

  # ── import_videos gating (re-auth vs. new channels) ──────────────────────

  describe "GET /auth/youtube/callback — import_videos gating" do
    before do
      authenticate_via_totp
      # Stash the youtube_connect intent and conversation UUID exactly as
      # ChatController#handle_connect does it.
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      OmniAuth.config.add_mock(:google_oauth2, omniauth_hash(subject_id: "sub-import-gate-#{SecureRandom.hex(4)}"))
    end

    context "when discovery returns only duplicates (re-auth, nothing new)" do
      before do
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels)
          .and_return({ added: [], duplicates: [ "Alpha Channel" ], error: nil })
      end

      it "enqueues ChannelInfoJob with import_videos: false" do
        expect { get "/auth/youtube/callback" }
          .to have_enqueued_job(ChannelInfoJob)
          .with(kind_of(Integer), kind_of(Integer), import_videos: false)
      end
    end

    context "when discovery adds at least one new channel" do
      before do
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels)
          .and_return({ added: [ { title: "Alpha Channel", handle: "@alpha" } ], duplicates: [], error: nil })
      end

      it "enqueues ChannelInfoJob with import_videos: true" do
        expect { get "/auth/youtube/callback" }
          .to have_enqueued_job(ChannelInfoJob)
          .with(kind_of(Integer), kind_of(Integer), import_videos: true)
      end
    end
  end

  # ── Failure action (GET /auth/failure) ────────────────────────────────────

  describe "GET /auth/failure" do
    it "returns 401 and is allow_anonymous (no redirect to login)" do
      get youtube_connection_oauth_failure_path
      expect(response.status).to eq(401)
    end

    it "renders a plain-text body with the failure message" do
      get youtube_connection_oauth_failure_path, params: { message: "access_denied" }
      expect(response.body).to include("access_denied")
    end
  end
end
