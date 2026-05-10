require "rails_helper"

# Settings → Google connection. This page is the SOLE entry point for
# adding channels into pito: `[+]` on /channels and `[manage]` on the
# Settings → Google card both land here. The URL-paste path is gone.
RSpec.describe "Settings::Youtube", type: :request do
  describe "GET /settings/youtube (manage page)" do
    context "with no YoutubeConnection" do
      it "renders the empty state with a connect button" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("no google account connected")
        expect(response.body).to include("[connect]")
      end

      it "renders the `google connection` heading (not `YouTube`)" do
        get settings_youtube_path
        expect(response.body).to include("<h1>google connection</h1>")
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
        expect(response.body).to include("your google grant was revoked")
        expect(response.body).to include("[reconnect]")
      end

      it "does NOT call the YouTube API" do
        expect(Youtube::Client).not_to receive(:new)
        get settings_youtube_path
      end

      # Bug-fix coverage — the manage page must keep rendering when the
      # connection is in needs_reauth state, with the picker section
      # replaced by a red `out of date or missing required scopes`
      # note that points at the same [reconnect] flow.
      it "renders 200 and replaces the picker with the scope-mismatch note" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(
          "your google authorization is out of date or missing required scopes"
        )
        expect(response.body).to include("[reconnect]")
      end

      it "still renders the `linked channels` listing (it does not depend on the API)" do
        valid_url = "https://www.youtube.com/channel/UCyyyyyyyyyyyyyyyyyyyyyy"
        Channel.create!(channel_url: valid_url,
                        youtube_connection_id: @connection.id)

        get settings_youtube_path
        expect(response.body).to include("linked channels")
        expect(response.body).to include("UCyyyyyyyyyyyyyyyyyyyyyy")
        expect(response.body).to include("[disconnect]")
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
            { id: "UCabc",
              snippet: { title: "Main Channel",
                         thumbnails: { default: { url: "https://yt3.example/avatar.png" } } },
              statistics: { subscriber_count: 1234 } }
          ],
          next_page_token: nil
        )
      end

      it "renders the connection metadata (email + scopes + last authorized)" do
        get settings_youtube_path
        expect(response.body).to include("u@example.test")
        expect(response.body).to include("connected as")
        expect(response.body).to include("last authorized")
        expect(response.body).to include("scopes")
      end

      it "renders the `select channels to add` heading and the multi-select form" do
        get settings_youtube_path
        expect(response.body).to include("select channels to add")
        expect(response.body).to match(/<form[^>]*action="#{Regexp.escape(settings_youtube_channels_path)}"/)
        expect(response.body).to include('name="youtube_channel_ids[]"')
        expect(response.body).to include("[<b>add channels</b>]")
      end

      it "renders one checkbox row per fetched YouTube channel" do
        get settings_youtube_path
        expect(response.body).to include("Main Channel")
        expect(response.body).to include('value="UCabc"')
        expect(response.body).to include("1,234")
      end

      it "renders the channel thumbnail when present" do
        get settings_youtube_path
        expect(response.body).to include("https://yt3.example/avatar.png")
      end

      it "renders already-linked channels with a disabled checkbox and `already added`" do
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
        expect(response.body).to include("already added")
        expect(response.body).to match(
          /<input[^>]*name="youtube_channel_ids\[\]"[^>]*value="UCabcdefghijklmnopqrstuv"[^>]*disabled/
        )
      end

      it "lists every channel currently linked to this connection" do
        valid_url = "https://www.youtube.com/channel/UCxxxxxxxxxxxxxxxxxxxxxx"
        Channel.create!(channel_url: valid_url,
                        youtube_connection_id: connection.id)

        get settings_youtube_path
        expect(response.body).to include("linked channels")
        expect(response.body).to include("UCxxxxxxxxxxxxxxxxxxxxxx")
        expect(response.body).to include("[disconnect]")
      end

      it "shows a muted note when no channels are linked yet" do
        get settings_youtube_path
        expect(response.body).to include("linked channels")
        expect(response.body).to include("no channels linked yet")
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

    context "when the YouTube API raises NeedsReauthError" do
      let(:user) { User.first }
      let(:connection) do
        create(:youtube_connection, user: user)
      end
      let(:client_double) { instance_double(Youtube::Client) }

      before do
        connection
        allow(Youtube::Client).to receive(:new).with(connection).and_return(client_double)
        # Simulate the bug-fix path — the client raises NeedsReauthError
        # AND flips `needs_reauth: true` on the connection (matching
        # the insufficient-scopes 403 branch in #execute_with_retry).
        allow(client_double).to receive(:channels_list) do
          connection.update_columns(needs_reauth: true)
          raise Youtube::NeedsReauthError, "insufficient authentication scopes"
        end
      end

      it "renders the page without 500ing" do
        get settings_youtube_path
        expect(response).to have_http_status(:ok)
      end

      it "renders the [reconnect] button and the red scope-mismatch note in the picker section" do
        get settings_youtube_path
        expect(response.body).to include("[reconnect]")
        expect(response.body).to include(
          "your google authorization is out of date or missing required scopes"
        )
      end

      it "still renders the linked-channels listing (no API dependency)" do
        valid_url = "https://www.youtube.com/channel/UCzzzzzzzzzzzzzzzzzzzzzz"
        Channel.create!(channel_url: valid_url,
                        youtube_connection_id: connection.id)

        get settings_youtube_path
        expect(response.body).to include("linked channels")
        expect(response.body).to include("UCzzzzzzzzzzzzzzzzzzzzzz")
        expect(response.body).to include("[disconnect]")
      end

      it "does NOT render the 'select channels to add' multi-select form" do
        # The picker form depends on `@youtube_channels`, which is
        # empty after the rescue. We want the red note in its place,
        # not the misleading `no channels found under this google
        # account` empty-state message.
        get settings_youtube_path
        expect(response.body).not_to include("no channels found under this google account")
        expect(response.body).not_to match(/<form[^>]*action="#{Regexp.escape(settings_youtube_channels_path)}"/)
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

  describe "POST /settings/youtube/channels (multi-select submit)" do
    let(:user) { User.first }
    let(:connection) do
      create(:youtube_connection, user: user)
    end

    before { connection }

    it "creates Channels for every selected YouTube id" do
      expect {
        post settings_youtube_channels_path,
             params: { youtube_channel_ids: %w[
               UCaaaaaaaaaaaaaaaaaaaaaa
               UCbbbbbbbbbbbbbbbbbbbbbb
             ] }
      }.to change { Channel.count }.by(2)

      urls = Channel.last(2).map(&:channel_url)
      expect(urls).to include(
        "https://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaaaa",
        "https://www.youtube.com/channel/UCbbbbbbbbbbbbbbbbbbbbbb"
      )
      Channel.last(2).each do |c|
        expect(c.youtube_connection_id).to eq(connection.id)
        expect(c.last_synced_at).to be_present
      end
    end

    it "redirects to /channels with a flash showing N channels added" do
      post settings_youtube_channels_path,
           params: { youtube_channel_ids: %w[UCaaaaaaaaaaaaaaaaaaaaaa UCbbbbbbbbbbbbbbbbbbbbbb] }
      expect(response).to redirect_to(channels_path)
      expect(flash[:notice]).to eq("2 channels added.")
    end

    it "redirects with a singular flash when exactly one channel is added" do
      post settings_youtube_channels_path,
           params: { youtube_channel_ids: %w[UCaaaaaaaaaaaaaaaaaaaaaa] }
      expect(response).to redirect_to(channels_path)
      expect(flash[:notice]).to eq("1 channel added.")
    end

    it "is idempotent: re-posting an already-linked id is a no-op" do
      post settings_youtube_channels_path,
           params: { youtube_channel_ids: %w[UCaaaaaaaaaaaaaaaaaaaaaa] }

      expect {
        post settings_youtube_channels_path,
             params: { youtube_channel_ids: %w[UCaaaaaaaaaaaaaaaaaaaaaa] }
      }.not_to change { Channel.count }

      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:notice]).to include("no new channels added")
    end

    it "accepts the legacy scalar `youtube_channel_id` and still works" do
      expect {
        post settings_youtube_channels_path,
             params: { youtube_channel_id: "UCaaaaaaaaaaaaaaaaaaaaaa" }
      }.to change { Channel.count }.by(1)
    end

    it "rejects an empty selection with an alert" do
      post settings_youtube_channels_path, params: {}
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("select at least one channel to add")
    end

    it "rejects an empty array selection with an alert" do
      post settings_youtube_channels_path, params: { youtube_channel_ids: [] }
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("select at least one channel to add")
    end

    it "rejects when no YoutubeConnection is present" do
      YoutubeConnection.delete_all
      post settings_youtube_channels_path,
           params: { youtube_channel_ids: %w[UCaaaaaaaaaaaaaaaaaaaaaa] }
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("google account is not connected")
    end

    it "rejects when the connection is in needs_reauth state" do
      connection.update_columns(needs_reauth: true)
      post settings_youtube_channels_path,
           params: { youtube_channel_ids: %w[UCaaaaaaaaaaaaaaaaaaaaaa] }
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("google account is not connected")
    end

    it "links an existing un-linked channel to this connection (flaw: bypass attempt)" do
      # Flaw scenario — a Channel row exists but is unlinked. A stale
      # form submit (or a malicious POST replay) targeting that row's
      # UC id should LINK it to the current connection, not duplicate
      # the row, and not surface an error.
      existing_url = "https://www.youtube.com/channel/UCcccccccccccccccccccccc"
      existing = Channel.create!(channel_url: existing_url,
                                 youtube_connection_id: nil)

      expect {
        post settings_youtube_channels_path,
             params: { youtube_channel_ids: %w[UCcccccccccccccccccccccc] }
      }.not_to change { Channel.count }

      existing.reload
      expect(existing.youtube_connection_id).to eq(connection.id)
      expect(response).to redirect_to(channels_path)
      expect(flash[:notice]).to eq("1 channel added.")
    end

    it "treats whitespace-only ids as empty selection" do
      post settings_youtube_channels_path,
           params: { youtube_channel_ids: [ "  ", "", nil ] }
      expect(response).to redirect_to(settings_youtube_path)
      expect(flash[:alert]).to include("select at least one channel to add")
    end
  end

  describe "GET /deletions/youtube_connection/:ids (confirmation)" do
    it "renders the action-screen confirmation page" do
      connection = create(:youtube_connection)
      channel = create(:channel, youtube_connection: connection)

      get deletions_path(type: "youtube_connection", ids: channel.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disconnect")
      expect(response.body).to include("[confirm disconnect]")
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
