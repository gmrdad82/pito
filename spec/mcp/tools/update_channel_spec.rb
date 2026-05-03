require "rails_helper"
require_relative "../../../app/mcp/tools/update_channel"

RSpec.describe Mcp::Tools::UpdateChannel do
  it "updates star with yes string" do
    channel = create(:channel, star: false)

    result = described_class.call(id: channel.id, star: "yes")

    expect(channel.reload.star).to eq(true)
    expect(result.content.first[:text]).to include("channel updated")
  end

  it "updates star=no" do
    channel = create(:channel, :starred)
    described_class.call(id: channel.id, star: "no")
    expect(channel.reload.star).to eq(false)
  end

  it "rejects connected=yes with structured error and does NOT update connected" do
    channel = create(:channel, connected: false)

    result = described_class.call(id: channel.id, connected: "yes")

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("Cannot alter `connected` via MCP")
    expect(channel.reload.connected).to eq(false)
  end

  it "rejects connected=no with structured error and does NOT update connected" do
    channel = create(:channel, connected: true)

    result = described_class.call(id: channel.id, connected: "no")

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("Cannot alter `connected` via MCP")
    expect(channel.reload.connected).to eq(true)
  end

  it "rejects star+connected together atomically — neither field changes" do
    channel = create(:channel, star: false, connected: false)

    result = described_class.call(id: channel.id, star: "yes", connected: "yes")

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("Cannot alter `connected` via MCP")
    channel.reload
    expect(channel.star).to eq(false)
    expect(channel.connected).to eq(false)
  end

  it "rejects star=true (raw boolean) with structured error" do
    channel = create(:channel)
    result = described_class.call(id: channel.id, star: true)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("must be 'yes' or 'no'")
    expect(channel.reload.star).to eq(false)
  end

  it "rejects star=\"1\" (legacy value) with structured error" do
    channel = create(:channel)
    result = described_class.call(id: channel.id, star: "1")
    expect(result.to_h[:isError]).to be true
  end

  it "schema declares star as enum yes/no strings and does NOT include connected" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    star = props[:star] || props["star"]
    expect((star[:type] || star["type"]).to_s).to eq("string")
    expect((star[:enum] || star["enum"]).map(&:to_s)).to contain_exactly("yes", "no")
    expect(props.key?(:connected) || props.key?("connected")).to eq(false)
  end

  it "rejects channel_url changes with a structured error" do
    channel = create(:channel)

    result = described_class.call(id: channel.id, channel_url: "https://www.youtube.com/channel/UC0000000000000000000000")

    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("channel_url cannot be changed")
  end

  it "returns error for missing channel" do
    result = described_class.call(id: 99999, star: true)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns error when no fields given" do
    channel = create(:channel)
    result = described_class.call(id: channel.id)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("no fields")
  end

  describe "input schema" do
    it "disallows additional properties (protocol-layer rejection of unknown keys)" do
      schema = described_class.input_schema.to_h
      expect(schema[:additionalProperties]).to eq(false).or eq("false")
    end
  end
end
