require "rails_helper"
require_relative "../../../app/mcp/tools/video_unlink"

RSpec.describe Mcp::Tools::VideoUnlink do
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }
  let(:game) { create(:game) }
  let!(:link) { create(:video_game_link, video: video, game: game) }

  it "preview when confirm: no — link survives" do
    described_class.call(ids: [ link.id ], confirm: "no")
    expect(VideoGameLink.where(id: link.id)).to exist
  end

  it "removes a single link with confirm: yes" do
    described_class.call(ids: [ link.id ], confirm: "yes")
    expect(VideoGameLink.where(id: link.id)).not_to exist
  end

  it "removes multiple links" do
    other_video = create(:video, channel: channel)
    link2 = create(:video_game_link, video: other_video, game: game)
    described_class.call(ids: [ link.id, link2.id ], confirm: "yes")
    expect(VideoGameLink.where(id: [ link.id, link2.id ])).to be_empty
  end

  it "tracks not_found ids" do
    result = described_class.call(ids: [ 999_999 ], confirm: "yes")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed["not_found"]).to eq([ 999_999 ])
  end

  it "rejects empty ids" do
    result = described_class.call(ids: [], confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(ids: [ link.id ], confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(ids: [ link.id ], confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
