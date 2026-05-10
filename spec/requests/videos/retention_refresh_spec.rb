require "rails_helper"

RSpec.describe "Video retention refresh", type: :request do
  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel) }

  describe "POST /videos/:video_id/analytics/retention/refresh" do
    it "enqueues VideoRetentionSync" do
      expect {
        post video_retention_refresh_path(video)
      }.to change(VideoRetentionSync.jobs, :size).by(1)
    end

    it "redirects back with a notice" do
      post video_retention_refresh_path(video)
      expect(response).to redirect_to(video_analytics_path(video))
    end

    it "404s on unknown video" do
      post "/videos/999999/analytics/retention/refresh"
      expect(response).to have_http_status(:not_found)
    end
  end
end
