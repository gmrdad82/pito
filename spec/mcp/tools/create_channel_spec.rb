require "rails_helper"
require_relative "../../../app/mcp/tools/create_channel"

# Phase 8 — tenant drop. Tools no longer reference a tenant.
RSpec.describe Mcp::Tools::CreateChannel do
  let(:valid_url) { "https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ" }

  it "creates a channel from a valid URL" do
    result = described_class.call(channel_url: valid_url)

    expect(Channel.count).to eq(1)
    channel = Channel.last
    expect(channel.channel_url).to eq(valid_url)
    expect(result.content.first[:text]).to include("channel created")
  end

  it "returns a structured error with the example URL when format is invalid" do
    result = described_class.call(channel_url: "https://youtube.com/@somehandle")

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("invalid channel_url")
    expect(result.content.first[:text]).to include("https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ")
    expect(Channel.count).to eq(0)
  end

  it "rejects an empty channel_url" do
    result = described_class.call(channel_url: "")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("invalid channel_url")
  end

  it "returns a uniqueness error when the URL already exists" do
    create(:channel, channel_url: valid_url)

    result = described_class.call(channel_url: valid_url)

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to match(/couldn't create|taken|already/i)
  end
end
