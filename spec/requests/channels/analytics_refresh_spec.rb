require "rails_helper"

RSpec.describe "Channel analytics refresh", type: :request do
  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  describe "POST /channels/:channel_id/analytics/refresh" do
    it "redirects back to the channel analytics page with a notice" do
      post channel_analytics_refresh_path(channel)
      expect(response).to redirect_to(channel_analytics_path(channel))
      follow_redirect!
      expect(flash[:notice] || response.body).to include("syncing")
    end

    it "enqueues ChannelAnalyticsSync" do
      expect {
        post channel_analytics_refresh_path(channel)
      }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
    end

    it "enqueues VideoAnalyticsSync for each active video" do
      v1 = create(:video, channel: channel)
      v2 = create(:video, channel: channel)
      expect {
        post channel_analytics_refresh_path(channel)
      }.to change(VideoAnalyticsSync.jobs, :size).by(2)
      enqueued = VideoAnalyticsSync.jobs.map { |j| j["args"].first }
      expect(enqueued).to match_array([ v1.id, v2.id ])
    end

    it "404s on unknown channel" do
      post "/channels/999999/analytics/refresh"
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      post channel_analytics_refresh_path(channel)
      expect(response).to redirect_to(login_path)
    end
  end
end
