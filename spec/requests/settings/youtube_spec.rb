require "rails_helper"

RSpec.describe "Settings::Youtube", type: :request do
  describe "GET /settings/youtube" do
    context "with no YoutubeConnection" do
      it "renders the empty state with a connect button" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no google account connected")
        expect(response.body).to include("[ connect ]")
      end
    end

    context "with a YoutubeConnection in needs_reauth state" do
      before do
        @user = User.first
        create(:youtube_connection, :needs_reauth, user: @user,
                                                   email: "u@example.test")
      end

      it "renders the red banner" do
        get settings_youtube_path
        expect(response.body).to include("your google grant was revoked")
        expect(response.body).to include("[ reconnect ]")
      end

      it "does NOT call the YouTube API" do
        expect(Youtube::Client).not_to receive(:new)
        get settings_youtube_path
      end
    end

    context "with a fresh YoutubeConnection" do
      let(:user) { User.first }
      let(:connection) do
        create(:youtube_connection, user: user,
               email: "u@example.test")
      end
      let(:client_double) { instance_double(Youtube::Client) }

      before do
        connection
        allow(Youtube::Client).to receive(:new).with(connection).and_return(client_double)
        allow(client_double).to receive(:channels_list).and_return(
          items: [
            { id: "UCabc", snippet: { title: "Main Channel" },
              statistics: { subscriber_count: 1234 } }
          ],
          next_page_token: nil
        )
      end

      it "renders the connected state with the email and the channel list" do
        get settings_youtube_path
        expect(response.body).to include("u@example.test")
        expect(response.body).to include("Main Channel")
        expect(response.body).to include("UCabc")
      end

      it "renders [ connect ] for unconnected channels" do
        get settings_youtube_path
        expect(response.body).to include("[ connect ]")
      end

      it "renders [ disconnect ] for already-connected channels" do
        valid_url = "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv"
        allow(client_double).to receive(:channels_list).and_return(
          items: [
            { id: "UCabcdefghijklmnopqrstuv",
              snippet: { title: "Main Channel" },
              statistics: { subscriber_count: 1234 } }
          ],
          next_page_token: nil
        )
        Channel.create!(channel_url: valid_url,
                        youtube_connection_id: connection.id)

        get settings_youtube_path
        expect(response.body).to include("[ disconnect ]")
      end
    end

    context "when the YouTube API raises QuotaExhaustedError" do
      let(:user) { User.first }
      let(:connection) do
        create(:youtube_connection, user: user)
      end
      let(:client_double) { instance_double(Youtube::Client) }

      before do
        connection
        allow(Youtube::Client).to receive(:new).with(connection).and_return(client_double)
        allow(client_double).to receive(:channels_list).and_raise(Youtube::QuotaExhaustedError)
      end

      it "renders the page with a red note (no 500)" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("YouTube api unavailable right now")
        expect(response.body).to include("quota exceeded")
      end
    end
  end

  describe "POST /settings/youtube/connect" do
    it "stashes the youtube_connection_oauth_intent and redirects to /auth/google_oauth2" do
      post settings_youtube_connect_path
      expect(response).to redirect_to("/auth/google_oauth2")
      expect(session[:youtube_connection_oauth_intent]).to eq("youtube_connect")
    end
  end

  describe "POST /settings/youtube/channels" do
    let(:user) { User.first }
    let(:connection) do
      create(:youtube_connection, user: user)
    end
    let(:client_double) { instance_double(Youtube::Client) }

    before do
      connection
      allow(Youtube::Client).to receive(:new).with(connection).and_return(client_double)
      allow(client_double).to receive(:channels_list).and_return(
        items: [ { id: "UCabcdefghijklmnopqrstuv", snippet: { title: "My Channel" } } ],
        next_page_token: nil
      )
    end

    it "creates a Channel with youtube_connection_id set" do
      expect {
        post settings_youtube_channels_path,
             params: { youtube_channel_id: "UCabcdefghijklmnopqrstuv" }
      }.to change { Channel.count }.by(1)

      channel = Channel.last
      expect(channel.channel_url).to eq("https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv")
      expect(channel.youtube_connection_id).to eq(connection.id)
      expect(channel.last_synced_at).to be_present
    end

    it "is idempotent: posting the same id twice does not create a duplicate" do
      post settings_youtube_channels_path, params: { youtube_channel_id: "UCabcdefghijklmnopqrstuv" }
      expect {
        post settings_youtube_channels_path, params: { youtube_channel_id: "UCabcdefghijklmnopqrstuv" }
      }.not_to change { Channel.count }
    end

    it "redirects with a flash" do
      post settings_youtube_channels_path, params: { youtube_channel_id: "UCabcdefghijklmnopqrstuv" }
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:notice]).to be_present
    end

    it "rejects when youtube_channel_id is missing" do
      post settings_youtube_channels_path, params: {}
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("missing youtube_channel_id")
    end
  end

  describe "GET /deletions/youtube_connection/:ids (confirmation)" do
    it "renders the action-screen confirmation page" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      get deletions_path(type: "youtube_connection", ids: channel.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disconnect")
      expect(response.body).to include("[ confirm disconnect ]")
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
  end
end
