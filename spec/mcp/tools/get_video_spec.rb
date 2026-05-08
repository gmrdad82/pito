require "rails_helper"
require_relative "../../../app/mcp/tools/get_video"

RSpec.describe Mcp::Tools::GetVideo do
  it "returns video detail with stats (post-A2 shape)" do
    channel = create(:channel)
    video = create(:video, channel: channel)
    create(:video_stat, video: video, date: Date.current, views: 100)

    result = described_class.call(id: video.id)
    data = JSON.parse(result.content.first[:text])

    # Phase 7 Path A2 — Video has no title/description/etc. The detail
    # surface returns id + youtube_video_id + star + last_synced_at +
    # stats.
    expect(data["id"]).to eq(video.id)
    expect(data["youtube_video_id"]).to eq(video.youtube_video_id)
    expect(data).not_to have_key("title")
    expect(data).not_to have_key("description")
    expect(data["stats"]).to be_an(Array)
    expect(data["stats"].first["views"]).to eq(100)
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999)
    expect(result.to_h[:isError]).to be true
  end
end
