require "rails_helper"
require_relative "../../../app/mcp/tools/video_diff_apply"

RSpec.describe Mcp::Tools::VideoDiffApply do
  let(:user) { Current.user }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: create(:youtube_connection, user: user))
  end
  let(:video) { create(:video, channel: channel, title: "local title") }

  let!(:diff) do
    create(:video_diff, video: video, payload: {
      "title" => { "pito" => "local title", "youtube" => "remote title" }
    })
  end

  it "is gated on the app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: video.to_param, decisions: { "title" => "youtube" }, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end

  it "returns a preview when confirm is not 'yes'" do
    result = described_class.call(id: video.to_param, decisions: { "title" => "youtube" })
    json = JSON.parse(result.content.first[:text])
    expect(json["preview"]).to be(true)
    expect(diff.reload.resolved_at).to be_nil
  end

  it "returns a preview when confirm is 'no'" do
    result = described_class.call(id: video.to_param, decisions: { "title" => "youtube" }, confirm: "no")
    json = JSON.parse(result.content.first[:text])
    expect(json["preview"]).to be(true)
  end

  it "applies youtube-wins on confirm: yes" do
    result = described_class.call(id: video.to_param, decisions: { "title" => "youtube" }, confirm: "yes")
    json = JSON.parse(result.content.first[:text])
    expect(json["ok"]).to be(true)
    expect(json["youtube_wins_fields"]).to eq([ "title" ])
    expect(video.reload.title).to eq("remote title")
    expect(diff.reload.resolved_at).to be_present
  end

  it "returns an error when there's no open diff" do
    diff.update!(resolved_at: 1.minute.ago, resolution_payload: { "title" => "youtube" })
    result = described_class.call(id: video.to_param, decisions: { "title" => "youtube" }, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("no open diff")
  end

  it "returns an error when the video is not found" do
    result = described_class.call(id: "no-such-video", decisions: { "title" => "youtube" }, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("video not found")
  end

  it "surfaces apply errors from the orchestrator (stale diff)" do
    result = described_class.call(
      id: video.to_param,
      decisions: { "title" => "youtube", "extra" => "youtube" },
      confirm: "yes"
    )
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("apply failed").or include("stale_diff")
  end
end
