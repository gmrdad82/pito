require "rails_helper"
require_relative "../../../app/mcp/tools/bundle_member_remove"

RSpec.describe Mcp::Tools::BundleMemberRemove do
  let!(:bundle) { create(:bundle) }
  let!(:game) { create(:game) }
  let!(:member) { bundle.bundle_members.create!(game: game) }

  it "preview when confirm: no — member survives" do
    described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: "no")
    expect(BundleMember.where(id: member.id)).to exist
  end

  it "removes the member with confirm: yes" do
    BundleCoverBuild.clear if defined?(BundleCoverBuild)
    described_class.call(bundle_id: bundle.id, game_id: game.id, confirm: "yes")
    expect(BundleMember.where(id: member.id)).not_to exist
  end

  it "404s when game not a member" do
    other = create(:game)
    result = described_class.call(bundle_id: bundle.id, game_id: other.id, confirm: "yes")
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
