require "rails_helper"
require_relative "../../../app/mcp/tools/list_channels"

RSpec.describe Mcp::Tools::ListChannels do
  it "returns empty array when no channels" do
    result = described_class.call
    data = JSON.parse(result.content.first[:text])
    expect(data).to eq([])
  end

  it "returns all channels with stats" do
    channel = create(:channel, subscriber_count: 1000, view_count: 50_000)
    create(:video, channel: channel)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    expect(data.first["title"]).to eq(channel.title)
    expect(data.first["subscriber_count"]).to eq(1000)
    expect(data.first["view_count"]).to eq(50_000)
  end
end
