require "rails_helper"
require_relative "../../../app/mcp/tools/get_video"

RSpec.describe Mcp::Tools::GetVideo do
  it "returns video detail with stats" do
    channel = create(:channel)
    video = create(:video, channel: channel)
    create(:video_stat, video: video, date: Date.current, views: 100)

    result = described_class.call(id: video.id)
    data = JSON.parse(result.content.first[:text])

    expect(data["title"]).to eq(video.title)
    expect(data["stats"]).to be_an(Array)
    expect(data["stats"].first["views"]).to eq(100)
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999)
    expect(result.to_h[:isError]).to be true
  end
end
