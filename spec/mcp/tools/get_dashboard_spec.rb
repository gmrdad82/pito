require "rails_helper"
require_relative "../../../app/mcp/tools/get_dashboard"

RSpec.describe Mcp::Tools::GetDashboard do
  it "returns dashboard analytics" do
    channel = create(:channel)
    video = create(:video, channel: channel)
    create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data["summary"]["channel_count"]).to eq(1)
    expect(data["summary"]["video_count"]).to eq(1)
    expect(data["top_videos"].first["total_views"]).to eq(500)
  end

  it "groups views_by_channel by channel id (post-revamp shape)" do
    channel = create(:channel)
    video = create(:video, channel: channel)
    create(:video_stat, video: video, date: Date.current, views: 500)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data["views_by_channel"]).to be_a(Hash)
    expect(data["views_by_channel"].keys.first).to eq(channel.id.to_s).or eq(channel.id)
  end

  it "accepts range parameter" do
    result = described_class.call(range: "7d")
    data = JSON.parse(result.content.first[:text])

    expect(data["summary"]["range"]).to eq("7d")
  end

  it "defaults invalid range to 30d" do
    result = described_class.call(range: "invalid")
    data = JSON.parse(result.content.first[:text])

    expect(data["summary"]["range"]).to eq("30d")
  end
end
