require "rails_helper"
require_relative "../../../app/mcp/tools/get_channel"

RSpec.describe Mcp::Tools::GetChannel do
  it "returns channel detail in the post-cleanup shape" do
    connection = create(:youtube_connection)
    channel = create(:channel, :starred, youtube_connection: connection)

    result = described_class.call(id: channel.id)
    data = JSON.parse(result.content.first[:text])

    # The derived `connected` field and the legacy `syncing` field
    # are both retired from the JSON wire shape.
    expect(data["id"]).to eq(channel.id)
    expect(data["channel_url"]).to eq(channel.channel_url)
    expect(data["star"]).to eq("yes")
    expect(data).not_to have_key("syncing")
    expect(data).not_to have_key("connected")
    expect(data.keys).to include("last_synced_at", "created_at", "updated_at")
  end

  it "returns structured error for missing channel" do
    result = described_class.call(id: 99999)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("not found")
  end
end
