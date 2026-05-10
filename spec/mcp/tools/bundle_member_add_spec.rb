require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_member_add"

RSpec.describe Mcp::Tools::BundleMemberAdd do
  let!(:bundle) { create(:bundle) }
  let!(:game) { create(:game) }

  it "preview when confirm: no — no member created" do
    expect {
      described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: "no")
    }.not_to change(BundleMember, :count)
  end

  it "creates a member and triggers cover rebuild with confirm: yes" do
    BundleCoverBuild.clear if defined?(BundleCoverBuild)
    expect {
      described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: "yes")
    }.to change(BundleMember, :count).by(1)
    expect(BundleCoverBuild.jobs.map { |j| j["args"].first }).to include(bundle.id)
  end

  it "rejects duplicate (game already a member)" do
    bundle.bundle_members.create!(game: game)
    result = described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing bundle" do
    result = described_class.call(bundle_id: 999_999, game_id: game.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "404s on missing game" do
    result = described_class.call(bundle_id: bundle.id, game_id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
