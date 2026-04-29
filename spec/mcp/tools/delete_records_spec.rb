require "rails_helper"
require_relative "../../../app/mcp/tools/delete_records"

RSpec.describe Mcp::Tools::DeleteRecords do
  it "deletes channels" do
    channel = create(:channel)

    result = described_class.call(type: "channel", ids: [ channel.id ])

    expect(Channel.count).to eq(0)
    expect(result.content.first[:text]).to include("deleted channel")
  end

  it "cascade-deletes channel videos" do
    channel = create(:channel)
    create(:video, channel: channel)

    described_class.call(type: "channel", ids: [ channel.id ])

    expect(Video.count).to eq(0)
  end

  it "deletes videos" do
    channel = create(:channel)
    video = create(:video, channel: channel)

    result = described_class.call(type: "video", ids: [ video.id ])

    expect(Video.count).to eq(0)
    expect(result.content.first[:text]).to include("deleted video")
  end

  it "reports missing IDs" do
    result = described_class.call(type: "channel", ids: [ 99999 ])
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns error for unknown type" do
    result = described_class.call(type: "playlist", ids: [ 1 ])
    expect(result.to_h[:isError]).to be true
  end
end
