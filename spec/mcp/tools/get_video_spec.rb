require "rails_helper"
require_relative "../../../app/mcp/tools/get_video"

RSpec.describe Mcp::Tools::GetVideo do
  it "returns video detail with stats (Phase 12 expanded shape)" do
    channel = create(:channel)
    video = create(:video, channel: channel, title: "MyVid")
    create(:video_stat, video: video, date: Date.current, views: 100)

    result = described_class.call(id: video.id)
    data = JSON.parse(result.content.first[:text])

    # Phase 12 — Video carries the writable subset (title, description,
    # tags, category_id, privacy_status, ...). The detail surface
    # mirrors the decorator's `as_detail_json`.
    expect(data["id"]).to eq(video.id)
    expect(data["youtube_video_id"]).to eq(video.youtube_video_id)
    expect(data["title"]).to eq("MyVid")
    expect(data).to have_key("description")
    expect(data).to have_key("tags")
    expect(data).to have_key("privacy_status")
    expect(data["stats"]).to be_an(Array)
    expect(data["stats"].first["views"]).to eq(100)
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999)
    expect(result.to_h[:isError]).to be true
  end
end
