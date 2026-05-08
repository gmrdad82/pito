require "rails_helper"
require_relative "../../../app/mcp/tools/update_video"

# Phase 7 Path A2 (literal full retract). update_video collapsed to
# `star:` only — title / description / privacy_status / tags /
# category_id / default_language are gone (the columns themselves
# are gone).
RSpec.describe Mcp::Tools::UpdateVideo do
  let!(:channel) { create(:channel) }

  it "updates star=yes" do
    video = create(:video, channel: channel, star: false)

    result = described_class.call(id: video.id, star: "yes")

    expect(video.reload.star?).to be(true)
    expect(result.content.first[:text]).to include("video updated")
  end

  it "updates star=no" do
    video = create(:video, :starred, channel: channel)
    described_class.call(id: video.id, star: "no")
    expect(video.reload.star?).to be(false)
  end

  it "rejects star=true (raw boolean)" do
    video = create(:video, channel: channel)
    result = described_class.call(id: video.id, star: true)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("must be 'yes' or 'no'")
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999, star: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "returns error when no fields given" do
    video = create(:video, channel: channel)
    result = described_class.call(id: video.id)
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("no fields")
  end

  it "schema does NOT include legacy metadata args" do
    schema = described_class.input_schema.to_h
    props = schema[:properties] || schema["properties"]
    %w[title description privacy_status tags category_id default_language].each do |k|
      expect(props.key?(k.to_sym) || props.key?(k)).to eq(false), "schema unexpectedly includes #{k}"
    end
  end
end
