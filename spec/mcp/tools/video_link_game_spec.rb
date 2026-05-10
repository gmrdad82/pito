require "rails_helper"
require_relative "../../../app/mcp/tools/video_link_game"

RSpec.describe Mcp::Tools::VideoLinkGame do
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }
  let(:game) { create(:game) }

  it "preview when confirm: no — no link created" do
    expect {
      described_class.call(video_id: video.id, game_id: game.id, confirm: "no")
    }.not_to change(VideoGameLink, :count)
  end

  it "creates a link with confirm: yes" do
    expect {
      described_class.call(video_id: video.id, game_id: game.id, confirm: "yes")
    }.to change(VideoGameLink, :count).by(1)

    link = VideoGameLink.last
    expect(link.video_id).to eq(video.id)
    expect(link.game_id).to eq(game.id)
    expect(link.is_primary).to be(false)
  end

  it "honors is_primary='yes'" do
    described_class.call(video_id: video.id, game_id: game.id, is_primary: "yes", confirm: "yes")
    expect(VideoGameLink.last.is_primary).to be(true)
  end

  it "rejects already-linked" do
    create(:video_game_link, video: video, game: game)
    result = described_class.call(video_id: video.id, game_id: game.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing video" do
    result = described_class.call(video_id: 999_999, game_id: game.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing game" do
    result = described_class.call(video_id: video.id, game_id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean is_primary smuggling" do
    result = described_class.call(video_id: video.id, game_id: game.id, is_primary: true, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(video_id: video.id, game_id: game.id, confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(video_id: video.id, game_id: game.id, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
