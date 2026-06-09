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
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
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

    it "returns 204, emits an echo then an error Event" do
      authenticate_via_totp
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }

      expect(response).to have_http_status(:no_content)

      echo = conversation.events.where(kind: :echo).last
      expect(echo).to be_present
      expect(echo.payload["text"]).to eq("/connect")

      expect(conversation.events.where(kind: :error).count).to eq(1)
      error_event = conversation.events.find_by(kind: :error)
      expect(error_event.payload["text"]).to include("not configured")
      expect(error_event.payload["credentials"]).to be_a(Hash)
      expect(error_event.payload["credentials"].keys).to include("client_id", "client_secret", "redirect_uri", "api_key")
    end
  end

  describe "POST /chat with /connect — credentials configured" do
    # /connect requires authentication. authenticate_via_totp sets the session cookie.

    before { authenticate_via_totp }

    it "returns a Turbo Stream navigate action targeting /auth/google_oauth2" do
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="navigate"')
      expect(response.body).to include("/auth/google_oauth2")
    end

    it "stashes the youtube_connect intent and conversation_uuid in session" do
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      expect(session[:youtube_connection_oauth_intent]).to eq("youtube_connect")
      expect(session[:youtube_connect_conversation_uuid]).to eq(conversation.uuid)
    end

    it "persists an echo Event for the /connect command" do
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      echo = conversation.events.where(kind: :echo).last
      expect(echo).to be_present
      expect(echo.payload["text"]).to eq("/connect")
    end

    it "clears the persisted draft so the chatbox doesn't rehydrate /connect after the OAuth round-trip" do
      conversation.update!(draft: "/connect")
      post chat_path, params: { input: "/connect", uuid: conversation.uuid }
      expect(conversation.reload.draft).to be_nil
    end
  end

  # ── OAuth callback ─────────────────────────────────────────────────────────

  describe "GET /auth/youtube/callback" do
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
        expect { get "/auth/youtube/callback" }.to change(YoutubeConnection, :count).by(1)
        expect(YoutubeConnection.last.google_subject_id).to eq("sub-abc")
      end

      it "creates Channel rows via youtube_channel_id" do
        expect { get "/auth/youtube/callback" }.to change(Channel, :count).by(1)
        expect(Channel.last.youtube_channel_id).to eq("UCaaa111")
      end

      it "persists a result Event on the conversation and redirects to /chat/:uuid" do
        get "/auth/youtube/callback"

        expect(response).to redirect_to(conversation_path(uuid: conversation.uuid))
        result_event = conversation.events.where(kind: :system).last
        expect(result_event).to be_present
        expect(result_event.payload["text"]).to include("Alpha Channel")
      end

      it "does NOT complete the turn (multi-stage flow: stats job will complete)" do
        get "/auth/youtube/callback"

        turn = conversation.turns.order(:position).last
        expect(turn.input_text).to eq("/connect")
        expect(turn.completed_at).to be_nil
      end

      it "enqueues ChannelInfoJob for the new connection and turn" do
        expect {
          get "/auth/youtube/callback"
        }.to have_enqueued_job(ChannelInfoJob)
      end

      it "upserts the connection (re-running /connect)" do
        get "/auth/youtube/callback"

        # Re-run /connect with same subject_id
        post chat_path, params: { input: "/connect", uuid: conversation.uuid }
        get "/auth/youtube/callback"

        expect(YoutubeConnection.where(google_subject_id: "sub-abc").count).to eq(1)
      end

      it "skips duplicate channels and emits an error event" do
        create(:channel, youtube_channel_id: "UCaaa111")
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels).and_return(
            { added: [], duplicates: [ "Alpha Channel" ], error: nil }
          )

        expect { get "/auth/youtube/callback" }.not_to change(Channel, :count)
        result = conversation.events.where(kind: :error).last
        expect(result).to be_present
        expect(result.payload["text"]).to include("is already connected")
      end

      it "completes the turn immediately for error cases (no follow-up stats)" do
        create(:channel, youtube_channel_id: "UCaaa111")
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels).and_return(
            { added: [], duplicates: [ "Alpha Channel" ], error: nil }
          )

        get "/auth/youtube/callback"
        turn = conversation.turns.order(:position).last
        expect(turn.completed_at).to be_present
      end

      it "does NOT enqueue ChannelInfoJob for error cases" do
        create(:channel, youtube_channel_id: "UCaaa111")
        allow_any_instance_of(YoutubeConnections::OauthCallbacksController)
          .to receive(:discover_and_link_channels).and_return(
            { added: [], duplicates: [ "Alpha Channel" ], error: nil }
          )

        expect {
          get "/auth/youtube/callback"
        }.not_to have_enqueued_job(ChannelInfoJob)
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
        get "/auth/youtube/callback"
        expect(YoutubeConnection.last.needs_reauth).to be true
        expect(response).to redirect_to(conversation_path(uuid: conversation.uuid))
      end
    end
  end

  # ── P56 — /connect --help does NOT start OAuth ────────────────────────────

  describe "POST /chat with /connect --help (P56)" do
    before { authenticate_via_totp }

    it "returns 204 No Content (not a Turbo Stream navigate)" do
      post chat_path, params: { input: "/connect --help", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT produce a Turbo Stream navigate response" do
      post chat_path, params: { input: "/connect --help", uuid: conversation.uuid }
      # 204 No Content responses have no body and no turbo-stream content type.
      expect(response.body).to be_empty
    end

    it "does NOT stash OAuth intent in session" do
      post chat_path, params: { input: "/connect --help", uuid: conversation.uuid }
      expect(session[:youtube_connection_oauth_intent]).to be_nil
    end

    it "emits a system Event with help content (not OAuth redirect)" do
      perform_enqueued_jobs { post chat_path, params: { input: "/connect --help", uuid: conversation.uuid } }
      system_events = conversation.events.where(kind: :system)
      expect(system_events).not_to be_empty
    end
  end
end
