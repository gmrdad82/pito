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

  # Phase 13 security fix-forward (F3) — per-video cache lock prevents
  # rapid-fire duplicate enqueues from a click-bomb. The lock TTL is
  # 60s and the lock is keyed by `analytics_refresh:video:<id>`.
  describe "rate-limit cache lock (F3)" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    it "writes a lock entry with a 60-second TTL on the first POST" do
      post video_analytics_refresh_path(video)
      lock_key = "analytics_refresh:video:#{video.id}"
      expect(memory_cache.exist?(lock_key)).to be(true)
    end

    it "enqueues the sync job when the lock is acquired" do
      expect {
        post video_analytics_refresh_path(video)
      }.to change(VideoAnalyticsSync.jobs, :size).by(1)
    end

    it "redirects with an alert when the lock is already held" do
      memory_cache.write("analytics_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)
      post video_analytics_refresh_path(video)
      expect(response).to redirect_to(video_analytics_path(video))
      follow_redirect!
      expect(flash[:alert] || response.body).to match(/already in progress/i)
    end

    it "does NOT enqueue any jobs when the lock is held" do
      memory_cache.write("analytics_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)
      expect {
        post video_analytics_refresh_path(video)
      }.not_to change(VideoAnalyticsSync.jobs, :size)
    end

    it "allows a subsequent POST after the lock expires" do
      lock_key = "analytics_refresh:video:#{video.id}"
      memory_cache.write(lock_key, 1, expires_in: 60.seconds)
      memory_cache.delete(lock_key)

      expect {
        post video_analytics_refresh_path(video)
      }.to change(VideoAnalyticsSync.jobs, :size).by(1)
    end

    it "scopes the lock per video (a second video is not blocked)" do
      other_video = create(:video, channel: channel)
      memory_cache.write("analytics_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)

      expect {
        post video_analytics_refresh_path(other_video)
      }.to change(VideoAnalyticsSync.jobs, :size).by(1)
    end
  end
end
