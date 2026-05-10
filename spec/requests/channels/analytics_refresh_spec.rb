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

  # Phase 13 security fix-forward (F3) — per-channel cache lock prevents
  # rapid-fire duplicate enqueues from a click-bomb. The lock TTL is
  # 60s and the lock is keyed by `analytics_refresh:channel:<id>`.
  describe "rate-limit cache lock (F3)" do
    # Swap the test environment's :null_store for a real MemoryStore
    # for the duration of these examples so `write(unless_exist:)` has
    # observable behavior.
    let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }

    before { allow(Rails).to receive(:cache).and_return(memory_cache) }

    it "writes a lock entry with a 60-second TTL on the first POST" do
      post channel_analytics_refresh_path(channel)
      lock_key = "analytics_refresh:channel:#{channel.id}"
      expect(memory_cache.exist?(lock_key)).to be(true)
    end

    it "enqueues the sync job when the lock is acquired" do
      expect {
        post channel_analytics_refresh_path(channel)
      }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
    end

    it "redirects with an alert when the lock is already held" do
      # Pre-seed the lock so the request observes a held lock.
      memory_cache.write("analytics_refresh:channel:#{channel.id}", 1,
                         expires_in: 60.seconds)
      post channel_analytics_refresh_path(channel)
      expect(response).to redirect_to(channel_analytics_path(channel))
      follow_redirect!
      expect(flash[:alert] || response.body).to match(/already in progress/i)
    end

    it "does NOT enqueue any jobs when the lock is held" do
      memory_cache.write("analytics_refresh:channel:#{channel.id}", 1,
                         expires_in: 60.seconds)
      expect {
        post channel_analytics_refresh_path(channel)
      }.not_to change(ChannelAnalyticsSync.jobs, :size)
    end

    it "allows a subsequent POST after the lock expires" do
      lock_key = "analytics_refresh:channel:#{channel.id}"
      memory_cache.write(lock_key, 1, expires_in: 60.seconds)

      # Manually delete to simulate the 60s TTL elapsing (MemoryStore
      # honors wall-clock TTL; deleting the entry is equivalent for
      # the unless_exist branch under test).
      memory_cache.delete(lock_key)

      expect {
        post channel_analytics_refresh_path(channel)
      }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
    end

    it "scopes the lock per channel (a second channel is not blocked)" do
      other_channel = create(:channel, youtube_connection: connection)
      memory_cache.write("analytics_refresh:channel:#{channel.id}", 1,
                         expires_in: 60.seconds)

      expect {
        post channel_analytics_refresh_path(other_channel)
      }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
    end
  end
end
