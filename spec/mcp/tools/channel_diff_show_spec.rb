require "rails_helper"
require_relative "../../../app/mcp/tools/channel_diff_show"

# Phase 7.5 §11i — MCP tool: channel_diff_show.
RSpec.describe Mcp::Tools::ChannelDiffShow do
  let(:user) { Current.user }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "local title",
           youtube_connection: create(:youtube_connection, user: user))
  end

  it "returns a JSON envelope with open: false when no diff exists" do
    result = described_class.call(id: channel.to_param)
    json = JSON.parse(result.content.first[:text])
    expect(json["open"]).to be(false)
    expect(json["channel_id"]).to eq(channel.id)
  end

  it "returns the diff payload when an open diff exists" do
    diff = create(:channel_diff, channel: channel, field_diffs: {
      "title" => { "pito" => "local title", "youtube" => "remote title" }
    })
    result = described_class.call(id: channel.to_param)
    json = JSON.parse(result.content.first[:text])
    expect(json["open"]).to be(true)
    expect(json["diff_id"]).to eq(diff.id)
    expect(json["fields"]).to eq([ "title" ])
    expect(json["writable_fields"]).to include("title")
    expect(json["unsupported_pito_fields"]).to include("banner_url")
  end

  it "is gated on the app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: channel.to_param)
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  it "returns a clear error when the channel is not found" do
    result = described_class.call(id: "no-such-channel")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("channel not found")
  end

  it "accepts an integer id as a string slug" do
    create(:channel_diff, channel: channel, field_diffs: {
      "title" => { "pito" => "p", "youtube" => "y" }
    })
    result = described_class.call(id: channel.id.to_s)
    json = JSON.parse(result.content.first[:text])
    expect(json["open"]).to be(true)
  end
end
