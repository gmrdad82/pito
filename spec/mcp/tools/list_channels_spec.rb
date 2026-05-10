require "rails_helper"
require_relative "../../../app/mcp/tools/list_channels"

RSpec.describe Mcp::Tools::ListChannels do
  it "returns empty array when no channels" do
    result = described_class.call
    data = JSON.parse(result.content.first[:text])
    expect(data).to eq([])
  end

  it "returns the new channel summary shape (booleans as yes/no strings)" do
    channel = create(:channel)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    row = data.first
    # `syncing` and the derived `connected` field are both retired
    # from the JSON shape.
    expect(row.keys).to include("id", "channel_url", "star", "last_synced_at", "created_at", "updated_at")
    expect(row).not_to have_key("syncing")
    expect(row).not_to have_key("connected")
    expect(row["channel_url"]).to eq(channel.channel_url)
    expect(row["star"]).to eq("no")
  end

  it "filters by star=yes" do
    starred = create(:channel, :starred)
    create(:channel)

    result = described_class.call(star: "yes")
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    expect(data.first["id"]).to eq(starred.id)
  end

  it "filters by star=no (excludes starred)" do
    create(:channel, :starred)
    plain = create(:channel)

    result = described_class.call(star: "no")
    data = JSON.parse(result.content.first[:text])

    expect(data.map { |r| r["id"] }).to eq([ plain.id ])
  end

  # The `connected` filter was retired alongside the derived
  # connected display surface — every channel is OAuth-linked by
  # definition now. The schema rejects the arg at the protocol layer
  # (`ArgumentError` from the keyword-argument signature).
  it "rejects a `connected` keyword arg (filter retired)" do
    expect { described_class.call(connected: "yes") }
      .to raise_error(ArgumentError, /connected/)
  end

  # Phase 7 Path A2 — the `syncing` column / filter is gone. Tool no
  # longer accepts a `syncing:` arg; the schema would reject it (or
  # it falls into **_extras and is ignored at the engine).

  it "rejects star=true (raw boolean) with structured error" do
    create(:channel, :starred)
    result = described_class.call(star: true)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("must be 'yes' or 'no'")
  end

  it "rejects star=\"1\" (legacy value) with structured error" do
    result = described_class.call(star: "1")
    expect(result.to_h[:isError]).to be true
  end

  it "schema declares star as an enum yes/no string" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    entry = props[:star] || props["star"]
    expect((entry[:type] || entry["type"]).to_s).to eq("string")
    expect((entry[:enum] || entry["enum"]).map(&:to_s)).to contain_exactly("yes", "no")
  end

  it "schema does NOT declare a syncing arg (column dropped in Path A2)" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    expect(props.keys.map(&:to_s)).not_to include("syncing")
  end

  it "schema does NOT declare a connected arg (derived surface retired)" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    expect(props.keys.map(&:to_s)).not_to include("connected")
  end

  it "respects limit and offset" do
    channels = Array.new(3) { create(:channel) }
    # created_at desc — newest first; freeze relative ordering.
    expected_ids = channels.reverse.map(&:id)

    result = described_class.call(limit: 2, offset: 0)
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(2)
    expect(data.map { |r| r["id"] }).to eq(expected_ids.first(2))

    result = described_class.call(limit: 2, offset: 2)
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    expect(data.map { |r| r["id"] }).to eq(expected_ids.last(1))
  end
end
