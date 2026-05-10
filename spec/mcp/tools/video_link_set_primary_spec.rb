require "rails_helper"
require_relative "../../../app/mcp/tools/video_link_set_primary"

RSpec.describe Mcp::Tools::VideoLinkSetPrimary do
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }
  let(:game) { create(:game) }
  let!(:link) { create(:video_game_link, video: video, game: game, is_primary: false) }

  it "preview when confirm: no — link unchanged" do
    described_class.call(id: link.id, is_primary: "yes", confirm: "no")
    expect(link.reload.is_primary).to be(false)
  end

  it "flips false → true with confirm: yes" do
    described_class.call(id: link.id, is_primary: "yes", confirm: "yes")
    expect(link.reload.is_primary).to be(true)
  end

  it "flips true → false" do
    link.update_column(:is_primary, true)
    described_class.call(id: link.id, is_primary: "no", confirm: "yes")
    expect(link.reload.is_primary).to be(false)
  end

  it "404s on missing link" do
    result = described_class.call(id: 999_999, is_primary: "yes", confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean is_primary smuggling" do
    result = described_class.call(id: link.id, is_primary: true, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: link.id, is_primary: "yes", confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: link.id, is_primary: "yes", confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
