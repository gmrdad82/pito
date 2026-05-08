require "rails_helper"
require_relative "../../../app/mcp/tools/list_videos"

RSpec.describe Mcp::Tools::ListVideos do
  let!(:channel) { create(:channel) }

  it "returns all videos with stats (post-A2 shape)" do
    video = create(:video, channel: channel)
    create(:video_stat, video: video, date: Date.current, views: 500)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    # Phase 7 Path A2 — Video JSON has no title; identify by youtube_video_id.
    expect(data.first["youtube_video_id"]).to eq(video.youtube_video_id)
    expect(data.first).not_to have_key("title")
    expect(data.first["views"]).to eq(500)
  end

  it "filters by channel_id" do
    create(:video, channel: channel)
    other_channel = create(:channel)
    create(:video, channel: other_channel)

    result = described_class.call(channel_id: channel.id)
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    expect(data.first["channel_id"]).to eq(channel.id)
  end

  it "respects limit" do
    3.times { create(:video, channel: channel) }

    result = described_class.call(limit: 2)
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(2)
  end
end
