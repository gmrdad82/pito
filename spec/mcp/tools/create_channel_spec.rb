require "rails_helper"
require_relative "../../../app/mcp/tools/create_channel"

RSpec.describe Mcp::Tools::CreateChannel do
  it "creates a channel" do
    result = described_class.call(title: "test channel", description: "a test")

    expect(Channel.count).to eq(1)
    channel = Channel.last
    expect(channel.title).to eq("test channel")
    expect(channel.youtube_channel_id).to start_with("local_")
    expect(result.content.first[:text]).to include("channel created")
  end

  it "returns error for blank title" do
    result = described_class.call(title: "")

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("couldn't create")
  end
end
