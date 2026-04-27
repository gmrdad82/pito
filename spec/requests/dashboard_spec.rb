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
        expect(json).to include("summary", "daily_views", "views_by_channel", "top_videos", "daily_engagement")
        expect(json["summary"]).to include("video_count" => 1, "channel_count" => 1)
      end

      it "returns JSON filtered by range" do
        get root_path(format: :json, range: "7d")
        json = JSON.parse(response.body)
        expect(json["summary"]["range"]).to eq("7d")
      end
    end
  end
end
