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

      it "renders the chart-sweep placeholder line" do
        get root_path
        # Chart-sweep dispatch (2026-05-07) — the daily-views / views-by-channel /
        # daily-engagement charts and the [7d / 30d / 90d / 1y / all] toolbar
        # have all been retired pending intentional metrics in a later phase.
        # The page now shows a single bracketed placeholder line.
        expect(response.body).to include("dashboard reset")
        expect(response.body).to include("charts return with intentional metrics in a later phase.")
      end

      it "no longer wires any chart machinery" do
        get root_path
        # Chart-sweep dispatch — none of the prior chart plumbing should ship.
        expect(response.body).not_to include('data-controller="chart-sync"')
        expect(response.body).not_to include("data-chart-sync-target")
        expect(response.body).not_to include("data-chart-id")
        expect(response.body).not_to include("daily views")
        expect(response.body).not_to include("views by channel")
        expect(response.body).not_to include("daily engagement")
        expect(response.body).not_to include("top videos")
      end

      it "ignores any range parameter (the toolbar is gone)" do
        get root_path(range: "7d")
        expect(response).to have_http_status(:ok)
        get root_path(range: "999d")
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON with the five-count summary shape" do
        get root_path(format: :json)
        json = JSON.parse(response.body)
        # Chart-sweep dispatch — daily_views / views_by_channel / daily_engagement
        # / range / top_videos are all dropped from the JSON shape. The remaining
        # payload mirrors the MCP `get_dashboard` tool: five required counts so
        # the pito CLI's `DashboardData` struct (no serde defaults) deserializes
        # cleanly.
        expect(json).to eq(
          "video_count" => 1,
          "channel_count" => 1,
          "project_count" => 0,
          "footage_count" => 0,
          "note_count" => 0
        )
      end
    end
  end

  # The pito-sh terminal client constructs `/dashboard.json` rather than
  # `/.json`. We expose a named alias to the same controller action.
  describe "GET /dashboard.json (pito-sh alias)" do
    let!(:channel) { create(:channel) }
    let!(:video) { create(:video, channel: channel) }
    let!(:project) { create(:project) }
    let!(:footage) { create(:footage, project: project) }
    let!(:note) { create(:note, project: project) }

    it "returns 200 JSON with the five-count shape" do
      get dashboard_path(format: :json)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      json = response.parsed_body
      expect(json).to eq(
        "video_count" => 1,
        "channel_count" => 1,
        "project_count" => 1,
        "footage_count" => 1,
        "note_count" => 1
      )
    end

    it "is reachable without an authentication token" do
      get dashboard_path(format: :json)
      expect(response).to have_http_status(:ok)
    end
  end
end
