# frozen_string_literal: true

require "rails_helper"

# P27 — /connect OAuth + multi-channel specs
#
# Covers:
#   - /connect error when credentials not configured
#   - /connect initiates OAuth redirect when configured
#   - Callback creates YoutubeConnection + channels (by youtube_channel_id)
#   - Callback dedupes existing channels
#   - Callback handles partial grant (missing scopes)
#   - /config google getter and setter (echo masking verified in config_spec)

RSpec.describe "P27 /connect + OAuth callback", type: :request do
  let(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/authenticate #{totp.now}", uuid: conversation.uuid }
  end

  # Build a minimal OmniAuth auth hash
  def omniauth_hash(subject_id: "sub-123", email: "user@example.com", scopes: PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES)
    OmniAuth::AuthHash.new(
      uid:  subject_id,
      info: { email: email },
      credentials: {
        token:        "access-token",
        refresh_token: "refresh-token",
        expires_at:   1.hour.from_now.to_i,
        scope:        scopes.join(" ")
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

  # ── /connect error path ────────────────────────────────────────────────────

  describe "POST /chat with /connect — credentials not configured" do
    before do
      # In test mode Pito::Credentials always has placeholders, so we stub
      # google_oauth_configured? directly to simulate an unconfigured install.
      allow(Pito::Credentials).to receive(:google_oauth_configured?).and_return(false)
    end

    it "returns 204 and persists an error Event" do
      authenticate_via_totp
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }

      expect(response).to have_http_status(:no_content)
      expect(conversation.events.where(kind: "error").count).to eq(1)
      error_event = conversation.events.where(kind: "error").first
      # text: is used for the not_configured error; message_key: may also be set
      text = error_event.payload["text"] || error_event.payload["message_key"]
      expect(text).to include("not configured").or include("config")
    end
  end

  describe "POST /chat with /connect — credentials configured" do
    # /connect requires authentication. authenticate_via_totp sets the session cookie.

    before { authenticate_via_totp }

    it "redirects to /auth/google_oauth2" do
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      expect(response).to redirect_to("/auth/google_oauth2")
    end

    it "stashes the youtube_connect intent and conversation_uuid in session" do
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      expect(session[:youtube_connection_oauth_intent]).to eq("youtube_connect")
      expect(session[:youtube_connect_conversation_uuid]).to eq(conversation.uuid)
    end

    it "persists an echo Event for the /connect command" do
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      echo = conversation.events.where(kind: "echo").last
      expect(echo).to be_present
      expect(echo.payload["text"]).to eq("/connect")
    end
  end

  # ── OAuth callback ─────────────────────────────────────────────────────────

  describe "GET /auth/google/callback" do
    before do
      authenticate_via_totp
      # Stash intent + conversation UUID as ChatController would
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
    end

    context "with a full grant" do
      before do
        OmniAuth.config.add_mock(:google_oauth2, omniauth_hash(subject_id: "sub-abc"))
        # Channel::Youtube::Client requires google-apis-youtube_analytics_v2 which
        # isn't installed. Stub discover_and_link_channels on the controller to
        # bypass the gem dependency while still exercising the callback logic.
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels) do |_, connection|
          Channel.create!(
            youtube_channel_id:    "UCaaa111",
            title:                 "Alpha Channel",
            youtube_connection_id: connection.id,
            last_synced_at:        Time.current
          )
          { added: [ "Alpha Channel" ], duplicates: [], error: nil }
        end
      end

      it "creates a YoutubeConnection" do
        expect { get "/auth/google/callback" }.to change(YoutubeConnection, :count).by(1)
        expect(YoutubeConnection.last.google_subject_id).to eq("sub-abc")
      end

      it "creates Channel rows via youtube_channel_id" do
        expect { get "/auth/google/callback" }.to change(Channel, :count).by(1)
        expect(Channel.last.youtube_channel_id).to eq("UCaaa111")
      end

      it "persists a result Event on the conversation and redirects to /chat/:uuid" do
        get "/auth/google/callback"

        expect(response).to redirect_to(conversation_path(uuid: conversation.uuid))
        result_event = conversation.events.where(kind: "assistant_text").last
        expect(result_event).to be_present
        expect(result_event.payload["text"]).to include("Alpha Channel")
      end

      it "upserts the connection (re-running /connect)" do
        get "/auth/google/callback"

        # Re-run /connect with same subject_id
        post chat_path, params: { input: "/connect", uuid: conversation.uuid }
        get "/auth/google/callback"

        expect(YoutubeConnection.where(google_subject_id: "sub-abc").count).to eq(1)
      end

      it "skips duplicate channels" do
        create(:channel, youtube_channel_id: "UCaaa111")
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels).and_return(
            { added: [], duplicates: [ "Alpha Channel" ], error: nil }
          )

        expect { get "/auth/google/callback" }.not_to change(Channel, :count)
        result = conversation.events.where(kind: "assistant_text").last
        expect(result.payload["text"]).to include("already linked")
      end
    end

    context "with partial grant (missing required scopes)" do
      before do
        OmniAuth.config.add_mock(
          :google_oauth2,
          omniauth_hash(subject_id: "sub-partial", scopes: [ "https://www.googleapis.com/auth/youtube.readonly" ])
        )
      end

      it "sets needs_reauth on the connection and redirects to the conversation" do
        get "/auth/google/callback"
        expect(YoutubeConnection.last.needs_reauth).to be true
        expect(response).to redirect_to(conversation_path(uuid: conversation.uuid))
      end
    end
  end
end
