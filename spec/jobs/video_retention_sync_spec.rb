require "rails_helper"

# Phase 13.2 — Analytics sync engine. Per-video V7 retention sync spec.
RSpec.describe VideoRetentionSync do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let(:video)      { create(:video, channel: channel, youtube_video_id: "vidret01", published_at: 30.days.ago) }
  let(:client_double) { instance_double(Youtube::AnalyticsClient) }

  before do
    allow(Youtube::AnalyticsClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:video_retention).and_return(
      column_headers: [
        { name: "elapsedVideoTimeRatio" },
        { name: "audienceWatchRatio" },
        { name: "relativeRetentionPerformance" },
        { name: "startedWatching" },
        { name: "stoppedWatching" }
      ],
      rows: [
        [ 0.0,  1.0,  1.0, 100, 0 ],
        [ 0.01, 0.95, 1.1, 95,  5 ],
        [ 0.02, 0.90, 1.2, 90, 10 ]
      ]
    )
  end

  it "fetches V7 for the video and upserts VideoRetention rows" do
    expect {
      described_class.new.perform(video.id)
    }.to change { VideoRetention.where(video_id: video.id).count }.by(3)
  end

  it "writes computed_at to (or near) the current time" do
    described_class.new.perform(video.id)
    row = VideoRetention.where(video_id: video.id).first
    expect(row.computed_at).to be_within(5.seconds).of(Time.current)
  end

  it "rejects multiple-video filters at the query-builder level" do
    expect {
      Youtube::AnalyticsQueryBuilder.video_retention_params(video_youtube_id: %w[a b])
    }.to raise_error(ArgumentError, /single video filter/)
  end

  it "exits early when the connection's needs_reauth is true" do
    connection.update_columns(needs_reauth: true)
    expect(client_double).not_to receive(:video_retention)
    described_class.new.perform(video.id)
  end

  it "is idempotent on a re-run for the same video" do
    described_class.new.perform(video.id)
    expect {
      described_class.new.perform(video.id)
    }.not_to change { VideoRetention.where(video_id: video.id).count }
  end
end
