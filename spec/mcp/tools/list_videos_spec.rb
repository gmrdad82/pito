require "rails_helper"
require_relative "../../../app/mcp/tools/list_videos"

RSpec.describe Mcp::Tools::ListVideos do
  let!(:channel) { create(:channel) }

  it "returns all videos with stats" do
    video = create(:video, channel: channel, published_at: 1.day.ago)
    create(:video_stat, video: video, date: Date.current, views: 500)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    expect(data.first["title"]).to eq(video.title)
    expect(data.first["total_views"]).to eq(500)
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
