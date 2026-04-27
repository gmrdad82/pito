require "rails_helper"

RSpec.describe "Channels", type: :request do
  describe "GET /channels (picker)" do
    it "returns 200" do
      get channels_path
      expect(response).to have_http_status(:ok)
    end

    it "has page title" do
      get channels_path
      expect(response.body).to include("<title>channels ~ pito</title>")
    end

    it "shows empty state when no channels" do
      get channels_path
      expect(response.body).to include("no channels yet")
    end

    it "includes bulk toggle link" do
      get channels_path
      expect(response.body).to include("bulk")
    end

    context "with channels" do
      let!(:channel) { create(:channel, :connected, subscriber_count: 1000, view_count: 50_000) }
      let!(:video) { create(:video, channel: channel) }

      it "displays the channels table" do
        get channels_path
        expect(response.body).to include(channel.title)
        expect(response.body).to include("1,000")
        expect(response.body).to include("50,000")
      end

      it "open link points to show page" do
        get channels_path
        expect(response.body).to include("/channels/#{channel.id}")
      end

      it "includes add link in table header" do
        get channels_path
        expect(response.body).to include(">add<")
      end

      it "renders bulk select controls" do
        get channels_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-max-panes-value="3"')
      end
    end

    context "with saved views" do
      let!(:channel1) { create(:channel) }
      let!(:channel2) { create(:channel) }
      let!(:saved_view) { create(:saved_view, kind: :channels, name: "test", url: "/channels/panes?ids=#{channel1.id},#{channel2.id}") }

      it "renders saved views section" do
        get channels_path
        expect(response.body).to include("saved views")
        expect(response.body).to include(channel1.title)
        expect(response.body).to include(channel2.title)
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel) }

      it "returns channel list as JSON" do
        get channels_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.first).to include("id", "title", "connected")
      end
    end
  end

  describe "GET /channels/:id (show)" do
    let!(:channel) { create(:channel, :connected, subscriber_count: 5000, view_count: 100_000) }
    let!(:video) { create(:video, channel: channel, published_at: 1.day.ago, duration_seconds: 300) }

    it "returns 200" do
      get channel_path(channel)
      expect(response).to have_http_status(:ok)
    end

    it "displays channel detail" do
      get channel_path(channel)
      expect(response.body).to include(channel.title)
      expect(response.body).to include(channel.youtube_channel_id)
      expect(response.body).to include("5,000")
      expect(response.body).to include("100,000")
    end

    it "displays channel videos" do
      get channel_path(channel)
      expect(response.body).to include(video.title)
    end

    it "shows breadcrumb" do
      get channel_path(channel)
      expect(response.body).to include("channels")
      expect(response.body).to include(channel.title)
    end

    it "includes delete link in breadcrumb actions" do
      get channel_path(channel)
      expect(response.body).to include("delete")
      expect(response.body).to include("/deletions")
    end

    it "includes add pane dialog when other channels exist" do
      create(:channel)
      get channel_path(channel)
      expect(response.body).to include("add a channel")
      expect(response.body).to include('data-controller="add-pane"')
    end

    it "returns 404 for unknown channel" do
      get channel_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON" do
      get channel_path(channel, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "title", "description", "videos")
    end
  end

  describe "GET /channels/new" do
    it "returns 200" do
      get new_channel_path
      expect(response).to have_http_status(:ok)
    end

    it "shows add form" do
      get new_channel_path
      expect(response.body).to include("new channel")
    end
  end

  describe "POST /channels" do
    it "creates channel and redirects" do
      post channels_path, params: { channel: { title: "new channel" } }
      channel = Channel.last
      expect(response).to redirect_to(channel_path(channel))
      expect(channel.title).to eq("new channel")
      expect(channel.youtube_channel_id).to start_with("local_")
    end

    it "re-renders new on invalid data" do
      post channels_path, params: { channel: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("couldn't create")
    end
  end

  describe "GET /channels/:id/edit" do
    let!(:channel) { create(:channel) }

    it "returns 200" do
      get edit_channel_path(channel)
      expect(response).to have_http_status(:ok)
    end

    it "shows edit form" do
      get edit_channel_path(channel)
      expect(response.body).to include("edit channel")
      expect(response.body).to include(channel.title)
    end
  end

  describe "PATCH /channels/:id" do
    let!(:channel) { create(:channel, title: "old title") }

    it "updates channel and redirects" do
      patch channel_path(channel), params: { channel: { title: "new title" } }
      expect(response).to redirect_to(channel_path(channel))
      expect(channel.reload.title).to eq("new title")
    end

    it "re-renders edit on invalid data" do
      patch channel_path(channel), params: { channel: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /channels/panes (multi-pane)" do
    let!(:channel1) { create(:channel) }
    let!(:channel2) { create(:channel) }

    it "redirects to show when single ID" do
      get panes_channels_path(ids: channel1.id)
      expect(response).to redirect_to(channel_path(channel1))
    end

    it "redirects to index when no IDs" do
      get panes_channels_path(ids: "")
      expect(response).to redirect_to(channels_path)
    end

    it "renders multi-pane view with space-separated IDs" do
      get panes_channels_path(ids: "#{channel1.id} #{channel2.id}")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include(channel2.title)
    end

    it "renders multi-pane view with comma-separated IDs" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include(channel2.title)
    end

    it "renders multi-pane view with plus-separated IDs" do
      get panes_channels_path(ids: "#{channel1.id}+#{channel2.id}")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include(channel2.title)
    end

    it "renders multi-pane view with mixed separators" do
      channel3 = create(:channel)
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}+#{channel3.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include(channel2.title)
      expect(response.body).to include(channel3.title)
    end

    it "ignores blank segments from consecutive separators" do
      get "#{panes_channels_path}?ids=#{channel1.id},,#{channel2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include(channel2.title)
    end

    it "generates comma-separated URLs in pane links" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include("ids=#{channel2.id},#{channel1.id}")
    end

    it "handles unknown IDs gracefully" do
      get "#{panes_channels_path}?ids=#{channel1.id},99999"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include("channel not found")
    end

    it "limits panes to max_panes" do
      ids = 6.times.map { create(:channel).id }
      get "#{panes_channels_path}?ids=#{ids.join(',')}"
      expect(response).to have_http_status(:ok)
    end

    it "includes focus link per pane" do
      get panes_channels_path(ids: "#{channel1.id} #{channel2.id}")
      expect(response.body).to include("focus")
    end

    it "includes add pane dialog with available channels" do
      channel3 = create(:channel)
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include("add a channel")
      expect(response.body).to include(channel3.title)
    end

    it "redirects single comma-separated ID to show" do
      get "#{panes_channels_path}?ids=#{channel1.id}"
      expect(response).to redirect_to(channel_path(channel1))
    end

    it "redirects when IDs param is just separators" do
      get "#{panes_channels_path}?ids=,,+"
      expect(response).to redirect_to(channels_path)
    end

    it "deduplicates display but preserves URL order" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id},#{channel1.id}"
      expect(response).to have_http_status(:ok)
    end

    it "strips whitespace around IDs" do
      get panes_channels_path(ids: " #{channel1.id} , #{channel2.id} ")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(channel1.title)
      expect(response.body).to include(channel2.title)
    end

    it "includes reorder arrows" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include("◀")
      expect(response.body).to include("▶")
    end

    it "includes minus link per pane" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include("−")
    end

    it "minus link on 2-pane redirects to show" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include(channel_path(channel2))
      expect(response.body).to include(channel_path(channel1))
    end

    it "minus link on 3+ pane links to panes with remaining IDs" do
      channel3 = create(:channel)
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id},#{channel3.id}"
      expect(response.body).to include("ids=#{channel2.id},#{channel3.id}")
    end

    it "reorder arrow swaps adjacent IDs in URL" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include("ids=#{channel2.id},#{channel1.id}")
    end

    it "shows save button when no saved view exists" do
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include(">save<")
    end

    it "shows delete link when saved view exists" do
      url = "/channels/panes?ids=#{channel1.id},#{channel2.id}"
      create(:saved_view, kind: :channels, name: "test view", url: url)
      get "#{panes_channels_path}?ids=#{channel1.id},#{channel2.id}"
      expect(response.body).to include("text-danger")
    end
  end
end
