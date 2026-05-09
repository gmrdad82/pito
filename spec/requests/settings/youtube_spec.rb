require "rails_helper"

RSpec.describe "Settings::Youtube", type: :request do
  describe "GET /settings/youtube" do
    context "with no GoogleIdentity" do
      it "renders the empty state with a connect button" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no google account connected")
        expect(response.body).to include("[ connect ]")
      end
    end

    context "with a GoogleIdentity in needs_reauth state" do
      before do
        @user = User.first
        create(:google_identity, :needs_reauth, user: @user, tenant: Current.tenant,
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

    context "with a fresh GoogleIdentity" do
      let(:user) { User.first }
      let(:identity) do
        create(:google_identity, user: user, tenant: Current.tenant,
               email: "u@example.test")
      end
      let(:client_double) { instance_double(Youtube::Client) }

      before do
        identity
        allow(Youtube::Client).to receive(:new).with(identity).and_return(client_double)
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
        # Phase 7 Path A2 — `connected: true` is gone; the OAuth-managed
        # state is just `oauth_identity_id` set.
        Channel.create!(tenant: Current.tenant,
                        channel_url: valid_url,
                        oauth_identity_id: identity.id)

        get settings_youtube_path
        expect(response.body).to include("[ disconnect ]")
      end
    end

    context "when the YouTube API raises QuotaExhaustedError" do
      let(:user) { User.first }
      let(:identity) do
        create(:google_identity, user: user, tenant: Current.tenant)
      end
      let(:client_double) { instance_double(Youtube::Client) }

      before do
        identity
        allow(Youtube::Client).to receive(:new).with(identity).and_return(client_double)
        allow(client_double).to receive(:channels_list).and_raise(Youtube::QuotaExhaustedError)
      end

      it "renders the page with a red note (no 500)" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("youtube api unavailable right now")
        expect(response.body).to include("quota exceeded")
      end
    end
  end

  describe "POST /settings/youtube/connect" do
    it "stashes the youtube_connect intent and redirects to /auth/google_oauth2" do
      post settings_youtube_connect_path
      expect(response).to redirect_to("/auth/google_oauth2")
      expect(session[:google_oauth_intent]).to eq("youtube_connect")
    end
  end

  describe "POST /settings/youtube/channels" do
    let(:user) { User.first }
    let(:identity) do
      create(:google_identity, user: user, tenant: Current.tenant)
    end
    let(:client_double) { instance_double(Youtube::Client) }

    before do
      identity
      allow(Youtube::Client).to receive(:new).with(identity).and_return(client_double)
      allow(client_double).to receive(:channels_list).and_return(
        items: [ { id: "UCabcdefghijklmnopqrstuv", snippet: { title: "My Channel" } } ],
        next_page_token: nil
      )
    end

    it "creates a Channel with oauth_identity_id set (post-A2: no separate connected boolean)" do
      expect {
        post settings_youtube_channels_path,
             params: { youtube_channel_id: "UCabcdefghijklmnopqrstuv" }
      }.to change { Channel.count }.by(1)

      channel = Channel.last
      expect(channel.channel_url).to eq("https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv")
      expect(channel.oauth_identity_id).to eq(identity.id)
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
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      get deletions_path(type: "youtube_connection", ids: channel.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disconnect")
      expect(response.body).to include("[ confirm disconnect ]")
    end
  end

  describe "DELETE /deletions/youtube_connection/:ids" do
    before { GoogleStubs.stub_revoke_success }

    it "clears oauth_identity_id, destroys the orphaned identity, redirects" do
      identity = create(:google_identity)
      channel = create(:channel, oauth_identity: identity)

      delete youtube_connection_disconnect_path(ids: channel.id)

      expect(response).to redirect_to(settings_youtube_path)
      channel.reload
      expect(channel.oauth_identity_id).to be_nil
      expect(GoogleIdentity.unscoped.where(id: identity.id).exists?).to be(false)
    end
  end
end
