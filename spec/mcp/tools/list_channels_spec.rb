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
    # Phase 9 — `syncing` is dropped from the JSON shape;
    # `connected` is derived from youtube_connection_id.
    expect(row.keys).to include("id", "channel_url", "star", "connected", "last_synced_at", "created_at", "updated_at")
    expect(row).not_to have_key("syncing")
    expect(row["channel_url"]).to eq(channel.channel_url)
    expect(row["star"]).to eq("no")
    expect(row["connected"]).to eq("no")
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

  it "filters by connected=yes" do
    connected = create(:channel, :connected)
    create(:channel)

    result = described_class.call(connected: "yes")
    data = JSON.parse(result.content.first[:text])

    expect(data.size).to eq(1)
    expect(data.first["id"]).to eq(connected.id)
  end

  # Phase 7 Path A2 — the `syncing` column / filter is gone. Tool no
  # longer accepts a `syncing:` arg; the schema would reject it (or
  # it falls into **_extras and is ignored at the engine).

  it "combines filters (intersection)" do
    create(:channel, :starred)
    create(:channel, :connected)
    both = create(:channel, :starred, :connected)

    result = described_class.call(star: "yes", connected: "yes")
    data = JSON.parse(result.content.first[:text])

    expect(data.map { |r| r["id"] }).to eq([ both.id ])
  end

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

  it "schema declares star/connected as enum yes/no strings" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    %i[star connected].each do |key|
      entry = props[key] || props[key.to_s]
      expect((entry[:type] || entry["type"]).to_s).to eq("string")
      expect((entry[:enum] || entry["enum"]).map(&:to_s)).to contain_exactly("yes", "no")
    end
  end

  it "schema does NOT declare a syncing arg (column dropped in Path A2)" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    expect(props.keys.map(&:to_s)).not_to include("syncing")
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
