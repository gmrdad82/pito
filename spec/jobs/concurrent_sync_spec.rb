require "rails_helper"

# Phase 13.2 — Analytics sync engine. Concurrency safety: Postgres'
# `upsert_all` resolves uniqueness conflicts via `ON CONFLICT DO
# UPDATE`. Two simultaneous jobs writing the same composite key do
# not duplicate rows.
#
# The threading model used here is conservative — Rails' connection
# pool needs an explicit `with_connection` per thread so the test
# suite doesn't leak connections.
RSpec.describe "concurrent analytics sync", type: :job do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, :connected, youtube_connection: connection) }
  let(:video)      { create(:video, channel: channel, youtube_video_id: "vidconcr", published_at: 30.days.ago) }
  let(:client_double) { instance_double(Youtube::AnalyticsClient) }

  before do
    allow(Youtube::AnalyticsClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:today_pt).and_return(Date.new(2026, 5, 10))

    allow(client_double).to receive(:channel_daily).and_return(
      column_headers: [ { name: "day" }, { name: "views" } ],
      rows: [ [ "2026-05-08", 100 ], [ "2026-05-09", 200 ] ]
    )
    allow(client_double).to receive(:channel_window_summary).and_return(
      column_headers: [ { name: "views" } ], rows: [ [ 600 ] ]
    )
    allow(client_double).to receive(:top_videos).and_return(
      column_headers: [ { name: "video" }, { name: "views" }, { name: "estimatedMinutesWatched" }, { name: "averageViewDuration" }, { name: "averageViewPercentage" }, { name: "subscribersGained" }, { name: "likes" }, { name: "comments" } ],
      rows: []
    )
    allow(client_double).to receive(:video_daily).and_return(
      column_headers: [ { name: "day" }, { name: "views" } ],
      rows: [ [ "2026-05-09", 100 ] ]
    )
    allow(client_double).to receive(:video_window_summary).and_return(
      column_headers: [ { name: "views" } ], rows: [ [ 100 ] ]
    )
    allow(client_double).to receive(:video_by_country).and_return(column_headers: [], rows: [])
    allow(client_double).to receive(:video_by_device_type).and_return(column_headers: [], rows: [])
    allow(client_double).to receive(:video_by_operating_system).and_return(column_headers: [], rows: [])
    allow(client_double).to receive(:video_by_traffic_source).and_return(column_headers: [], rows: [])
    allow(client_double).to receive(:video_by_subscribed_status).and_return(column_headers: [], rows: [])
    allow(client_double).to receive(:video_demographics).and_return(column_headers: [], rows: [])
  end

  it "two ChannelAnalyticsSync runs for the same channel do not duplicate ChannelDaily rows" do
    ChannelAnalyticsSync.new.perform(channel.id)
    expect {
      ChannelAnalyticsSync.new.perform(channel.id)
    }.not_to change { ChannelDaily.where(channel_id: channel.id).count }
  end

  it "two VideoAnalyticsSync runs for the same video do not duplicate VideoDaily rows" do
    VideoAnalyticsSync.new.perform(video.id)
    expect {
      VideoAnalyticsSync.new.perform(video.id)
    }.not_to change { VideoDaily.where(video_id: video.id).count }
  end
end
