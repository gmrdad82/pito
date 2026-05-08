require "rails_helper"

# Phase 7 Path A2 (literal full retract). Video is now a thin
# YouTube-reference record. The CRUD form (new / create / edit /
# update) is retired — Videos are created only via the Phase 7C
# connect-channel sync flow. The index/show/destroy/panes/stats
# surfaces survive.
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

    it "does not include the legacy [+] add button" do
      get videos_path
      # Phase 7 Path A2 — Video CRUD is retired. The [+] new-video
      # action on /videos is gone; Videos are created via the
      # connect-channel sync flow only.
      expect(response.body).not_to include('class="bl">+</span>')
    end

    context "with videos" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3) }

      it "displays the video table" do
        get videos_path
        expect(response.body).to include(video.youtube_video_id)
        expect(response.body).to include(channel.channel_url)
        expect(response.body).to include("500")
      end

      it "renders the name column header as a server-side sort link" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        link = html.css("thead a").find { |a| a.text.strip == "name" }
        expect(link).not_to be_nil
        expect(link["href"]).to include("sort=id")
      end

      it "renders the name cell as a link to the video show page" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        name_cell = row.css("td")[1]
        link = name_cell.css("a").first
        expect(link).not_to be_nil
        expect(link["href"]).to eq(video_path(video))
        expect(link.text.strip).to eq(video.id.to_s)
      end

      it "stamps data-turbo-frame=_top on the video name link (escape the frame on row click)" do
        get videos_path
        html = Nokogiri::HTML.fragment(response.body)
        row = html.css("tbody tr").first
        name_cell = row.css("td")[1]
        link = name_cell.css("a").first
        expect(link["data-turbo-frame"]).to eq("_top")
      end

      it "exposes `id` in VideosController::ALLOWED_SORTS so server-side sort honors it" do
        expect(VideosController::ALLOWED_SORTS).to include("id" => "videos.id")
      end

      it "renders always-on bulk select checkboxes" do
        get videos_path
        expect(response.body).to include('data-bulk-select-target="checkbox"')
        expect(response.body).to include('data-bulk-select-target="headerCheckbox"')
      end
    end

    context "JSON format" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }

      it "returns video list as JSON in the post-A2 shape" do
        get videos_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to be_an(Array)
        row = json.first
        expect(row).to include(
          "id", "youtube_video_id", "channel_id", "channel_url",
          "star", "views", "likes", "comments", "watch_time_minutes",
          "last_synced_at", "trend"
        )
        expect(row).not_to have_key("title")
        expect(row).not_to have_key("privacy_status")
      end
    end
  end

  describe "GET /videos/:id (show)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }

    it "returns 200" do
      get video_path(video)
      expect(response).to have_http_status(:ok)
    end

    it "displays video detail" do
      get video_path(video)
      expect(response.body).to include(video.youtube_video_id)
    end

    it "shows breadcrumb" do
      get video_path(video)
      expect(response.body).to include("video ##{video.id}")
    end

    it "includes [-] delete link in breadcrumb actions" do
      get video_path(video)
      expect(response.body).to include("/deletions/video/#{video.id}")
    end

    it "does NOT include an [e] edit link (CRUD form is retired)" do
      get video_path(video)
      expect(response.body).not_to include("[e]")
      expect(response.body).not_to include("edit_video")
    end

    it "returns 404 for unknown video" do
      get video_path(id: 99999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns detail JSON" do
      get video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to include("id", "youtube_video_id", "channel_id", "stats")
    end

    it "wraps the single pane in pane-strip > pane" do
      get video_path(video)
      expect(response.body).to include('<div class="pane-strip">')
    end
  end

  describe "DELETE /videos/:id" do
    let!(:video) { create(:video) }

    it "deletes the video and redirects" do
      expect {
        delete video_path(video)
      }.to change(Video, :count).by(-1)
      expect(response).to redirect_to(videos_path)
    end

    it "JSON returns 204" do
      v = create(:video)
      delete video_path(v, format: :json)
      expect(response).to have_http_status(:no_content)
    end
  end

  # Phase 7 Path A2 — verify the dropped routes are no longer mounted.
  describe "retired video CRUD routes" do
    let!(:video) { create(:video) }

    it "/videos/new resolves to the show action (no longer the new form)" do
      # Phase 7 Path A2 — the /new route is gone; `/videos/new` now
      # falls through to /videos/:id with id="new", which 404s when
      # Video.find(:new) misses.
      hit = Rails.application.routes.recognize_path("/videos/new", method: :get)
      expect(hit).to include(controller: "videos", action: "show")
    end

    it "/videos/:id/edit is not a recognized route" do
      expect {
        Rails.application.routes.recognize_path("/videos/#{video.id}/edit", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end

    it "POST /videos is not a recognized route" do
      expect {
        Rails.application.routes.recognize_path("/videos", method: :post)
      }.to raise_error(ActionController::RoutingError)
    end

    it "PATCH /videos/:id is not a recognized route" do
      expect {
        Rails.application.routes.recognize_path("/videos/#{video.id}", method: :patch)
      }.to raise_error(ActionController::RoutingError)
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
  end

  describe "GET /videos/:id/stats(.json)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 100, likes: 5, comments: 2, watch_time_minutes: 50) }

    it "returns the stats JSON in the pito-shape" do
      get stats_video_path(video, format: :json)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      row = json.first
      expect(row).to include("date", "views", "likes", "comments", "watch_time_minutes")
    end

    it "redirects HTML requests to the video show page" do
      get stats_video_path(video)
      expect(response).to redirect_to(video_path(video))
    end
  end
end
