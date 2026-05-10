require "rails_helper"

RSpec.describe "Video analytics refresh", type: :request do
  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel) }

  describe "POST /videos/:video_id/analytics/refresh" do
    it "redirects back to the video analytics page with a notice" do
      post video_analytics_refresh_path(video)
      expect(response).to redirect_to(video_analytics_path(video))
    end

    it "enqueues VideoAnalyticsSync" do
      expect {
        post video_analytics_refresh_path(video)
      }.to change(VideoAnalyticsSync.jobs, :size).by(1)
    end

    it "404s on unknown video" do
      post "/videos/999999/analytics/refresh"
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      post video_analytics_refresh_path(video)
      expect(response).to redirect_to(login_path)
    end
  end
end
