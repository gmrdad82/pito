require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /" do
    it "returns 200" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "shows empty state when no videos" do
      get root_path
      expect(response.body).to include("no videos yet")
    end

    context "with data" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3) }

      it "shows summary counts" do
        get root_path
        expect(response.body).to include("1 videos across 1 channels")
      end

      it "has the default page title" do
        get root_path
        expect(response.body).to include("<title>pito ~ best YouTube tool</title>")
      end

      it "renders chart toolbar with default 30d range" do
        get root_path
        expect(response.body).to include("7d")
        expect(response.body).to include("30d")
        expect(response.body).to include("90d")
      end

      it "renders chart containers" do
        get root_path
        expect(response.body).to include("daily views")
        expect(response.body).to include("views by channel")
        expect(response.body).to include("top videos")
        expect(response.body).to include("daily engagement")
      end

      it "wires the chart-sync Stimulus controller and per-chart slugs" do
        get root_path
        expect(response.body).to include('data-controller="chart-sync"')
        expect(response.body).to include('data-chart-id="daily-views"')
        expect(response.body).to include('data-chart-id="views-by-channel"')
        expect(response.body).to include('data-chart-id="top-videos"')
        expect(response.body).to include('data-chart-id="daily-engagement"')
      end

      it "wires sync-capable line charts as chart-sync targets" do
        get root_path
        # The 3 line charts opt into crosshair sync; the bar chart (top-videos) does not
        expect(response.body.scan('data-chart-sync-target="chart"').size).to eq(3)
        expect(response.body).to include('data-chart-id="daily-views" data-chart-sync-target="chart"')
        expect(response.body).to include('data-chart-id="views-by-channel" data-chart-sync-target="chart"')
        expect(response.body).to include('data-chart-id="daily-engagement" data-chart-sync-target="chart"')
      end

      it "renders one [ ] sync bracketed-checkbox per sync-capable chart" do
        get root_path
        # Each sync-capable chart has a CheckboxComponent (md-check) wired as a chart-sync checkbox target
        expect(response.body.scan('data-chart-sync-target="checkbox"').size).to eq(3)
        expect(response.body).to include('data-chart-sync-target="checkbox"')
        expect(response.body).to include('data-chart-id="daily-views"')
        expect(response.body).to include('data-action="change-&gt;chart-sync#toggle"')
        # Bracketed design-system style — md-check class with link variant for
        # blue brackets-and-label coloring (matches filter chip color)
        expect(response.body).to include("md-check md-check-link")
        expect(response.body).to include("md-check-indicator")
      end

      it "accepts range parameter" do
        get root_path(range: "7d")
        expect(response).to have_http_status(:ok)
      end

      it "falls back to 30d for invalid range" do
        get root_path(range: "999d")
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON with chart data" do
        get root_path(format: :json)
        json = JSON.parse(response.body)
        expect(json).to include(
          "video_count", "channel_count", "range",
          "daily_views", "views_by_channel", "top_videos", "daily_engagement"
        )
        expect(json["video_count"]).to eq(1)
        expect(json["channel_count"]).to eq(1)
      end

      it "returns daily_views as an array of [date, count] tuples" do
        get root_path(format: :json)
        json = JSON.parse(response.body)
        expect(json["daily_views"]).to be_an(Array)
        json["daily_views"].each do |pair|
          expect(pair).to be_an(Array)
          expect(pair.length).to eq(2)
          expect(pair.first).to be_a(String)
          expect(pair.last).to be_a(Integer)
        end
      end

      it "returns views_by_channel as an array of [label, [[date, count], ...]] tuples" do
        get root_path(format: :json)
        json = JSON.parse(response.body)
        expect(json["views_by_channel"]).to be_an(Array)
        json["views_by_channel"].each do |entry|
          expect(entry).to be_an(Array)
          expect(entry.length).to eq(2)
          expect(entry.first).to be_a(String)
          expect(entry.last).to be_an(Array)
        end
      end

      it "returns top_videos with title + views (Rust shape)" do
        get root_path(format: :json)
        json = JSON.parse(response.body)
        expect(json["top_videos"]).to be_an(Array)
        json["top_videos"].each do |row|
          expect(row).to include("title", "views")
          expect(row["views"]).to be_a(Integer)
        end
      end

      it "returns daily_engagement as an object with likes + comments tuple arrays" do
        get root_path(format: :json)
        json = JSON.parse(response.body)
        expect(json["daily_engagement"]).to be_a(Hash)
        expect(json["daily_engagement"]).to include("likes", "comments")
        expect(json["daily_engagement"]["likes"]).to be_an(Array)
        expect(json["daily_engagement"]["comments"]).to be_an(Array)
      end

      it "returns JSON filtered by range" do
        get root_path(format: :json, range: "7d")
        json = JSON.parse(response.body)
        expect(json["range"]).to eq("7d")
      end
    end
  end

  # The pito-sh terminal client constructs `/dashboard.json` rather than
  # `/.json`. We expose a named alias to the same controller action.
  describe "GET /dashboard.json (pito-sh alias)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }

    it "returns 200 JSON identical to the root JSON shape" do
      get dashboard_path(format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      json = response.parsed_body
      expect(json).to include(
        "video_count", "channel_count", "range",
        "daily_views", "views_by_channel", "top_videos", "daily_engagement"
      )
    end

    it "honors the range parameter" do
      get dashboard_path(format: :json, range: "7d")
      expect(response.parsed_body["range"]).to eq("7d")
    end

    it "is reachable without an authentication token" do
      get dashboard_path(format: :json)
      expect(response).to have_http_status(:ok)
    end
  end
end
