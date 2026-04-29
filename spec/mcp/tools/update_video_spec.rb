require "rails_helper"
require_relative "../../../app/mcp/tools/update_video"

RSpec.describe Mcp::Tools::UpdateVideo do
  let!(:channel) { create(:channel) }

  it "updates video title" do
    video = create(:video, channel: channel, title: "old")

    result = described_class.call(id: video.id, title: "new")

    expect(video.reload.title).to eq("new")
    expect(result.content.first[:text]).to include("video updated")
  end

  it "updates multiple fields" do
    video = create(:video, channel: channel)

    described_class.call(id: video.id, title: "changed", privacy_status: "unlisted")

    video.reload
    expect(video.title).to eq("changed")
    expect(video.privacy_status).to eq("unlisted")
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999, title: "x")
    expect(result.to_h[:isError]).to be true
  end
end
