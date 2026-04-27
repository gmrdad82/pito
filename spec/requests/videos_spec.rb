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
      expect(response.body).to include("actions")
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
  end
end
