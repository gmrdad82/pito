require "rails_helper"

# Phase 13.2 — Analytics sync engine. Backfill helper for catching
# gaps after a re-authorization or filling initial history.
RSpec.describe Backfill::AnalyticsRange do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, :connected, youtube_connection: connection) }
  let(:video)      { create(:video, channel: channel, published_at: 30.days.ago) }
  let(:from)       { 30.days.ago.to_date }
  let(:to)         { 1.day.ago.to_date }

  before do
    channel
    video
    Sidekiq::Worker.clear_all
  end

  it "enqueues ChannelAnalyticsSync for every channel under the connection" do
    expect {
      described_class.call(connection: connection, from: from, to: to)
    }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
  end

  it "enqueues VideoAnalyticsSync for every active video under the connection" do
    expect {
      described_class.call(connection: connection, from: from, to: to)
    }.to change(VideoAnalyticsSync.jobs, :size).by(1)
  end

  it "respects the channels: scope filter" do
    other_channel = create(:channel, :connected, youtube_connection: connection)
    described_class.call(
      connection: connection, from: from, to: to,
      channels: [ channel ]
    )
    queued_args = ChannelAnalyticsSync.jobs.map { |j| j["args"].first }
    expect(queued_args).to include(channel.id)
    expect(queued_args).not_to include(other_channel.id)
  end

  it "respects the videos: scope filter" do
    other_video = create(:video, channel: channel, published_at: 5.days.ago)
    described_class.call(
      connection: connection, from: from, to: to,
      videos: [ video ]
    )
    queued_args = VideoAnalyticsSync.jobs.map { |j| j["args"].first }
    expect(queued_args).to include(video.id)
    expect(queued_args).not_to include(other_video.id)
  end

  it "returns the count of enqueued jobs" do
    count = described_class.call(connection: connection, from: from, to: to)
    expect(count).to eq(2) # 1 channel + 1 active video
  end

  it "raises when from > to" do
    expect {
      described_class.call(connection: connection, from: to, to: from)
    }.to raise_error(ArgumentError, /from must be <= to/)
  end

  it "raises when connection is not active (needs_reauth)" do
    connection.update_columns(needs_reauth: true)
    expect {
      described_class.call(connection: connection, from: from, to: to)
    }.to raise_error(ArgumentError, /not active/)
  end
end
