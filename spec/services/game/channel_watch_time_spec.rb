# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::ChannelWatchTime do
  let(:channel) { create(:channel) }
  let(:v1) { create(:video, channel: channel) }
  let(:v2) { create(:video, channel: channel) }
  let(:client) { instance_double(Channel::Youtube::AnalyticsClient) }

  before do
    allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client)
    # Real cache so the 1-day caching is exercised (test env defaults to null store).
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  it "maps video.id => lifetime watch-hours from the per-channel fetch" do
    allow(client).to receive(:top_videos).and_return([
      { video_id: v1.youtube_video_id, estimated_minutes_watched: 6_000 }, # 100h
      { video_id: v2.youtube_video_id, estimated_minutes_watched: 1_800 }  # 30h
    ])
    result = described_class.hours_for(videos: [ v1, v2 ])
    expect(result[v1.id]).to eq(100.0)
    expect(result[v2.id]).to eq(30.0)
  end

  it "caches the per-channel fetch for a day (one API call across repeats)" do
    allow(client).to receive(:top_videos)
      .and_return([ { video_id: v1.youtube_video_id, estimated_minutes_watched: 60 } ])
    described_class.hours_for(videos: [ v1 ])
    described_class.hours_for(videos: [ v1 ])
    expect(client).to have_received(:top_videos).once
  end

  it "returns {} for a channel with no connection (graceful)" do
    orphan = create(:channel, :orphan)
    vo     = create(:video, channel: orphan)
    expect(described_class.hours_for(videos: [ vo ])).to eq({})
  end

  it "returns {} when the API call fails (graceful)" do
    allow(client).to receive(:top_videos).and_raise(StandardError, "boom")
    expect(described_class.hours_for(videos: [ v1 ])).to eq({})
  end

  it "omits videos with zero watch-minutes" do
    allow(client).to receive(:top_videos)
      .and_return([ { video_id: v1.youtube_video_id, estimated_minutes_watched: 0 } ])
    expect(described_class.hours_for(videos: [ v1 ])).to eq({})
  end
end
