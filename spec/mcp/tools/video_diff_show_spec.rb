require "rails_helper"
require_relative "../../../app/mcp/tools/video_diff_show"

RSpec.describe Mcp::Tools::VideoDiffShow do
  let(:user) { Current.user }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: create(:youtube_connection, user: user))
  end
  let(:video) { create(:video, channel: channel, title: "local title") }

  it "returns a JSON envelope with open: false when no diff exists" do
    result = described_class.call(id: video.to_param)
    json = JSON.parse(result.content.first[:text])
    expect(json["open"]).to be(false)
  end

  it "returns the diff payload when an open diff exists" do
    diff = create(:video_diff, video: video, payload: {
      "title" => { "pito" => "local title", "youtube" => "remote title" }
    })
    result = described_class.call(id: video.to_param)
    json = JSON.parse(result.content.first[:text])
    expect(json["open"]).to be(true)
    expect(json["diff_id"]).to eq(diff.id)
    expect(json["fields"]).to eq([ "title" ])
    expect(json["writable_fields"]).to include("title")
  end

  it "is gated on the app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: video.to_param)
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  it "returns a clear error when the video is not found" do
    result = described_class.call(id: "no-such-video")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("video not found")
  end

  it "accepts an integer id as a string slug" do
    create(:video_diff, video: video, payload: {
      "title" => { "pito" => "p", "youtube" => "y" }
    })
    result = described_class.call(id: video.id.to_s)
    json = JSON.parse(result.content.first[:text])
    expect(json["open"]).to be(true)
  end
end
