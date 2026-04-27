require "rails_helper"

RSpec.describe "Videos", type: :request do
  describe "GET /videos" do
    it "returns 200" do
      get videos_path
      expect(response).to have_http_status(:ok)
    end

    it "has page title" do
      get videos_path
      expect(response.body).to include("<title>videos ~ pito</title>")
    end

    it "shows empty state when no videos" do
      get videos_path
      expect(response.body).to include("no videos yet")
    end

    it "includes bulk toggle link" do
      get videos_path
      expect(response.body).to include("bulk")
    end

    context "with videos" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel, published_at: 1.day.ago, duration_seconds: 600) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3) }

      it "displays the video table" do
        get videos_path
        expect(response.body).to include(video.title)
        expect(response.body).to include(channel.title)
        expect(response.body).to include("500")
      end

      it "includes open link per row" do
        get videos_path
        expect(response.body).to include("open")
      end

      it "includes add link in table header" do
        get videos_path
        expect(response.body).to include(">add<")
      end

      it "shows duration" do
        get videos_path
        expect(response.body).to include("10:00")
      end

      it "renders bulk select checkboxes (hidden by default)" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
      end

      it "renders bulk actions bar (hidden by default)" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="actions"')
        expect(response.body).to include("delete")
      end

      it "passes max_panes value to bulk-select controller" do
        get videos_path
        expect(response.body).to include('data-bulk-select-max-panes-value="3"')
      end
    end

    context "with saved views" do
      let!(:channel) { create(:channel) }
      let!(:video1) { create(:video, channel: channel) }
      let!(:video2) { create(:video, channel: channel) }
      let!(:saved_view) { create(:saved_view, kind: :videos, name: "test", url: "/videos/panes?ids=#{video1.id},#{video2.id}") }

      it "renders saved views section" do
        get videos_path
        expect(response.body).to include("saved views")
        expect(response.body).to include(video1.title)
        expect(response.body).to include(video2.title)
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }

      it "returns video list as JSON" do
        get videos_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        expect(json.first).to include("id", "title", "channel_title")
      end
    end
  end

  describe "GET /videos/:id (show)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, published_at: 1.day.ago, duration_seconds: 300) }

    it "returns 200" do
      get video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "displays video detail" do
      get video_path(video)
      expect(response.body).to include(video.title)
      expect(response.body).to include(video.youtube_video_id)
    end

    it "shows breadcrumb" do
      get video_path(video)
      expect(response.body).to include("videos")
      expect(response.body).to include(video.title)
    end

    it "includes delete link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include("delete")
      expect(response.body).to include("/deletions")
    end

    it "includes add pane dialog when other videos exist" do
      create(:video, channel: channel)
      get video_path(video)
      expect(response.body).to include("add a video")
      expect(response.body).to include('data-controller="add-pane"')
    end

    it "returns 404 for unknown video" do
      get video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON" do
      get video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "title", "description", "stats")
    end
  end

  describe "GET /videos/new" do
    it "returns 200" do
      get new_video_path
      expect(response).to have_http_status(:ok)
    end

    it "shows add form" do
      get new_video_path
      expect(response.body).to include("new video")
    end
  end

  describe "POST /videos" do
    let!(:channel) { create(:channel) }

    it "creates video and redirects" do
      post videos_path, params: { video: { title: "new video", channel_id: channel.id } }
      video = Video.last
      expect(response).to redirect_to(video_path(video))
      expect(video.title).to eq("new video")
      expect(video.youtube_video_id).to start_with("local_")
    end

    it "re-renders new on invalid data" do
      post videos_path, params: { video: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("couldn't create")
    end
  end

  describe "GET /videos/:id/edit" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }

    it "returns 200" do
      get edit_video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "shows edit form" do
      get edit_video_path(video)
      expect(response.body).to include("edit video")
      expect(response.body).to include(video.title)
    end
  end

  describe "PATCH /videos/:id" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel, title: "old title") }

    it "updates video and redirects" do
      patch video_path(video), params: { video: { title: "new title" } }
      expect(response).to redirect_to(video_path(video))
      expect(video.reload.title).to eq("new title")
    end

    it "re-renders edit on invalid data" do
      patch video_path(video), params: { video: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /videos/panes (multi-pane)" do
    let!(:channel) { create(:channel) }
    let!(:video1) { create(:video, channel: channel) }
    let!(:video2) { create(:video, channel: channel) }

    it "redirects to show when single ID" do
      get panes_videos_path(ids: video1.id)
      expect(response).to redirect_to(video_path(video1))
    end

    it "redirects to index when no IDs" do
      get panes_videos_path(ids: "")
      expect(response).to redirect_to(videos_path)
    end

    it "renders multi-pane view with comma-separated IDs" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video1.youtube_video_id)
      expect(response.body).to include(video2.youtube_video_id)
    end

    it "includes focus link per pane" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("focus")
    end

    it "includes reorder arrows" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("◀")
      expect(response.body).to include("▶")
    end

    it "includes minus link per pane" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("−")
    end

    it "handles unknown IDs gracefully" do
      get "#{panes_videos_path}?ids=#{video1.id},99999"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(video1.title)
      expect(response.body).to include("video not found")
    end

    it "includes add pane dialog with available videos" do
      video3 = create(:video, channel: channel)
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("add a video")
      expect(response.body).to include(video3.title)
    end

    it "shows save button when no saved view exists" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include(">save<")
    end

    it "shows delete link when saved view exists" do
      url = "/videos/panes?ids=#{video1.id},#{video2.id}"
      create(:saved_view, kind: :videos, name: "test view", url: url)
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("text-danger")
    end

    it "reorder arrow swaps adjacent IDs in URL" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include("ids=#{video2.id},#{video1.id}")
    end

    it "minus link on 2-pane redirects to show" do
      get "#{panes_videos_path}?ids=#{video1.id},#{video2.id}"
      expect(response.body).to include(video_path(video2))
      expect(response.body).to include(video_path(video1))
    end
  end
end
