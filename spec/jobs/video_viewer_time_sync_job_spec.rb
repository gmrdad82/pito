require "rails_helper"

# Phase 26 §01g — viewer-time sync job spec.
RSpec.describe VideoViewerTimeSyncJob do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:video)      { create(:video, channel: channel, youtube_video_id: "vt_abc") }
  let(:client_double) { instance_double(Youtube::AnalyticsClient) }

  before do
    allow(Youtube::AnalyticsClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:today_pt).and_return(Date.new(2026, 5, 10))
  end

  describe "happy path — single video, sync upserts buckets" do
    before do
      allow(client_double).to receive(:video_viewer_time).and_return(
        column_headers: [
          { name: "day" }, { name: "hour" },
          { name: "views" }, { name: "estimatedMinutesWatched" }
        ],
        rows: [
          # 2026-05-09 is a Saturday (wday=6). Two hours of data.
          [ "2026-05-09", 14, 100, 50 ],
          [ "2026-05-09", 15, 200, 80 ]
        ]
      )
    end

    it "upserts one row per (dow, hod) pair" do
      expect {
        described_class.new.perform(video.id)
      }.to change { VideoViewerTimeBucket.where(video_id: video.id).count }.by(2)
    end

    it "persists view counts and watch_time (estimatedMinutesWatched x 60)" do
      described_class.new.perform(video.id)
      bucket = VideoViewerTimeBucket.find_by(
        video_id: video.id, day_of_week_utc: 6, hour_of_day_utc: 14
      )
      expect(bucket).not_to be_nil
      expect(bucket.view_count).to eq(100)
      expect(bucket.watch_time_seconds).to eq(50 * 60)
    end

    it "stamps last_synced_at" do
      described_class.new.perform(video.id)
      bucket = VideoViewerTimeBucket.find_by(video_id: video.id, hour_of_day_utc: 14)
      expect(bucket.last_synced_at).to be_within(5.seconds).of(Time.current)
    end

    it "is idempotent on re-run — no duplicate rows" do
      described_class.new.perform(video.id)
      expect {
        described_class.new.perform(video.id)
      }.not_to change { VideoViewerTimeBucket.where(video_id: video.id).count }
    end

    it "aggregates two same-hour-on-different-days into separate dow rows" do
      allow(client_double).to receive(:video_viewer_time).and_return(
        column_headers: [
          { name: "day" }, { name: "hour" },
          { name: "views" }, { name: "estimatedMinutesWatched" }
        ],
        rows: [
          [ "2026-05-09", 10, 100, 50 ],  # Sat, dow=6, hod=10
          [ "2026-05-08", 10, 200, 80 ]   # Fri, dow=5, hod=10
        ]
      )
      described_class.new.perform(video.id)
      dows = VideoViewerTimeBucket.where(video_id: video.id).pluck(:day_of_week_utc).sort
      expect(dows).to eq([ 5, 6 ])
    end

    it "sums duplicate same-(dow, hod) rows in one run" do
      allow(client_double).to receive(:video_viewer_time).and_return(
        column_headers: [
          { name: "day" }, { name: "hour" },
          { name: "views" }, { name: "estimatedMinutesWatched" }
        ],
        rows: [
          [ "2026-05-09", 10, 100, 50 ],  # Sat, dow=6, hod=10
          [ "2026-05-02", 10, 200, 80 ]   # Sat, dow=6, hod=10 (earlier week)
        ]
      )
      described_class.new.perform(video.id)
      bucket = VideoViewerTimeBucket.find_by(video_id: video.id, day_of_week_utc: 6, hour_of_day_utc: 10)
      expect(bucket.view_count).to eq(300)
      expect(bucket.watch_time_seconds).to eq((50 + 80) * 60)
    end
  end

  describe "sad path — auth error" do
    it "exits cleanly when AnalyticsClient raises AuthError" do
      allow(client_double).to receive(:video_viewer_time)
        .and_raise(Youtube::AnalyticsClient::AuthError)
      expect {
        described_class.new.perform(video.id)
      }.not_to raise_error
      expect(VideoViewerTimeBucket.where(video_id: video.id).count).to eq(0)
    end
  end

  describe "sad path — connection guarding" do
    it "no-ops when the video does not exist" do
      expect {
        described_class.new.perform(999_999_999)
      }.not_to raise_error
    end

    it "no-ops when the channel has no youtube_connection" do
      orphan_channel = create(:channel)
      orphan_video = create(:video, channel: orphan_channel)
      expect(Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(orphan_video.id)
    end

    it "no-ops when the connection needs reauth" do
      connection.update!(needs_reauth: true)
      expect(Youtube::AnalyticsClient).not_to receive(:new)
      described_class.new.perform(video.id)
    end
  end

  describe "empty response" do
    it "creates no rows when the API returns an empty rows array" do
      allow(client_double).to receive(:video_viewer_time).and_return(
        column_headers: [ { name: "day" }, { name: "hour" }, { name: "views" } ],
        rows: []
      )
      expect {
        described_class.new.perform(video.id)
      }.not_to change { VideoViewerTimeBucket.count }
    end
  end
end
