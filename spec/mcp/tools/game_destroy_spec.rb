require "rails_helper"
require_relative "../../../app/mcp/tools/game_destroy"

RSpec.describe Mcp::Tools::GameDestroy do
  let!(:game) { create(:game, title: "ToDie") }

  it "preview when confirm: no — game survives" do
    described_class.call(id: game.id, confirm: "no")
    expect(Game.where(id: game.id)).to exist
  end

  it "destroys with confirm: yes" do
    described_class.call(id: game.id, confirm: "yes")
    expect(Game.where(id: game.id)).not_to exist
  end

  it "404s on missing id" do
    result = described_class.call(id: 999_999, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: game.id, confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: game.id, confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
