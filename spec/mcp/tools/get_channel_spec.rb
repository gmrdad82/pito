require "rails_helper"
require_relative "../../../app/mcp/tools/get_channel"

RSpec.describe Mcp::Tools::GetChannel do
  it "returns channel detail with videos" do
    channel = create(:channel)
    video = create(:video, channel: channel)

    result = described_class.call(id: channel.id)
    data = JSON.parse(result.content.first[:text])

    expect(data["title"]).to eq(channel.title)
    expect(data["videos"].size).to eq(1)
    expect(data["videos"].first["title"]).to eq(video.title)
  end

  it "returns error for missing channel" do
    result = described_class.call(id: 99999)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("not found")
  end
end
