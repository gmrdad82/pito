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

  # Phase 13 security fix-forward (F3) — per-video retention cache
  # lock. The lock key (`retention_refresh:video:<id>`) is intentionally
  # distinct from the V1-V8 analytics lock so the two refresh buttons
  # do not block each other.
  describe "rate-limit cache lock (F3)" do
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    it "writes a lock entry with a 60-second TTL on the first POST" do
      post video_retention_refresh_path(video)
      lock_key = "retention_refresh:video:#{video.id}"
      expect(memory_cache.exist?(lock_key)).to be(true)
    end

    it "enqueues the sync job when the lock is acquired" do
      expect {
        post video_retention_refresh_path(video)
      }.to change(VideoRetentionSync.jobs, :size).by(1)
    end

    it "redirects with an alert when the lock is already held" do
      memory_cache.write("retention_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)
      post video_retention_refresh_path(video)
      expect(response).to redirect_to(video_analytics_path(video))
      follow_redirect!
      expect(flash[:alert] || response.body).to match(/already in progress/i)
    end

    it "does NOT enqueue any jobs when the lock is held" do
      memory_cache.write("retention_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)
      expect {
        post video_retention_refresh_path(video)
      }.not_to change(VideoRetentionSync.jobs, :size)
    end

    it "allows a subsequent POST after the lock expires" do
      lock_key = "retention_refresh:video:#{video.id}"
      memory_cache.write(lock_key, 1, expires_in: 60.seconds)
      memory_cache.delete(lock_key)

      expect {
        post video_retention_refresh_path(video)
      }.to change(VideoRetentionSync.jobs, :size).by(1)
    end

    it "does not block when only the V1-V8 analytics lock is held" do
      memory_cache.write("analytics_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)
      expect {
        post video_retention_refresh_path(video)
      }.to change(VideoRetentionSync.jobs, :size).by(1)
    end

    it "scopes the lock per video (a second video is not blocked)" do
      other_video = create(:video, channel: channel)
      memory_cache.write("retention_refresh:video:#{video.id}", 1,
                         expires_in: 60.seconds)

      expect {
        post video_retention_refresh_path(other_video)
      }.to change(VideoRetentionSync.jobs, :size).by(1)
    end
  end
end
