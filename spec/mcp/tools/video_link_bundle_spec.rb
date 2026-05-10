require "rails_helper"
require_relative "../../../app/mcp/tools/video_link_bundle"

RSpec.describe Mcp::Tools::VideoLinkBundle do
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }
  let(:bundle) { create(:bundle) }

  it "preview when confirm: no" do
    expect {
      described_class.call(video_id: video.id, bundle_id: bundle.id, confirm: "no")
    }.not_to change(VideoGameLink, :count)
  end

  it "creates a bundle link with confirm: yes" do
    expect {
      described_class.call(video_id: video.id, bundle_id: bundle.id, confirm: "yes")
    }.to change(VideoGameLink, :count).by(1)

    link = VideoGameLink.last
    expect(link.bundle_id).to eq(bundle.id)
    expect(link.game_id).to be_nil
    expect(link.link_bundle?).to be(true)
  end

  it "rejects already-linked" do
    create(:video_game_link, :bundle, video: video, bundle: bundle)
    result = described_class.call(video_id: video.id, bundle_id: bundle.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing video" do
    result = described_class.call(video_id: 999_999, bundle_id: bundle.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing bundle" do
    result = described_class.call(video_id: video.id, bundle_id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean is_primary smuggling" do
    result = described_class.call(video_id: video.id, bundle_id: bundle.id, is_primary: true, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(video_id: video.id, bundle_id: bundle.id, confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(video_id: video.id, bundle_id: bundle.id, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
