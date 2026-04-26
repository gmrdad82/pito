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

    context "with seeded data" do
      let!(:channel) { create(:channel) }
      let!(:video) { create(:video, channel: channel, published_at: 1.day.ago) }
      let!(:stat) { create(:video_stat, video: video, date: Date.current, views: 100, likes: 10, comments: 5) }

      it "displays the video table" do
        get root_path
        expect(response.body).to include(video.title)
        expect(response.body).to include(channel.title)
        expect(response.body).to include("100")
      end

      it "shows video count summary" do
        get root_path
        expect(response.body).to include("1 videos")
      end

      it "includes sortable table markup" do
        get root_path
        expect(response.body).to include("sortable-table")
      end

      it "has the default page title" do
        get root_path
        expect(response.body).to include("<title>pito ~ best YouTube tool</title>")
      end
    end
  end
end
