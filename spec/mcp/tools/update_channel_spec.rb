require "rails_helper"
require_relative "../../../app/mcp/tools/update_channel"

RSpec.describe Mcp::Tools::UpdateChannel do
  it "updates channel title" do
    channel = create(:channel, title: "old")

    result = described_class.call(id: channel.id, title: "new")

    expect(channel.reload.title).to eq("new")
    expect(result.content.first[:text]).to include("channel updated")
  end

  it "returns error for missing channel" do
    result = described_class.call(id: 99999, title: "x")
    expect(result.to_h[:isError]).to be true
  end

  it "returns error when no fields given" do
    channel = create(:channel)
    result = described_class.call(id: channel.id)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("no fields")
  end
end
