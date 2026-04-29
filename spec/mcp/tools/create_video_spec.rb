require "rails_helper"
require_relative "../../../app/mcp/tools/create_video"

RSpec.describe Mcp::Tools::CreateVideo do
  let!(:channel) { create(:channel) }

  it "creates a video" do
    result = described_class.call(title: "test video", channel_id: channel.id)

    expect(Video.count).to eq(1)
    video = Video.last
    expect(video.title).to eq("test video")
    expect(video.channel).to eq(channel)
    expect(video.youtube_video_id).to start_with("local_")
    expect(result.content.first[:text]).to include("video created")
  end

  it "creates video with all fields" do
    result = described_class.call(
      title: "full video",
      channel_id: channel.id,
      description: "desc",
      privacy_status: "unlisted",
      tags: "tag1,tag2",
      default_language: "es"
    )

    video = Video.last
    expect(video.privacy_status).to eq("unlisted")
    expect(video.tags).to eq("tag1,tag2")
    expect(video.default_language).to eq("es")
  end

  it "returns error for missing title" do
    result = described_class.call(title: "", channel_id: channel.id)
    expect(result.to_h[:isError]).to be true
  end
end
