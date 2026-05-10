require "rails_helper"
require_relative "../../../app/mcp/tools/game_update_local"

RSpec.describe Mcp::Tools::GameUpdateLocal do
  let!(:game) { create(:game) }

  it "preview when confirm: no — does not mutate" do
    described_class.call(id: game.id, notes: "hello", confirm: "no")
    expect(game.reload.notes).to be_blank
  end

  it "applies notes / played_at / hours_of_footage_manual with confirm: yes" do
    described_class.call(
      id: game.id, notes: "great game",
      played_at: "2025-01-01",
      hours_of_footage_manual: 5,
      confirm: "yes"
    )
    game.reload
    expect(game.notes).to eq("great game")
    expect(game.played_at.to_s).to eq("2025-01-01")
    expect(game.hours_of_footage_manual).to eq(5)
  end

  it "rejects when no fields supplied" do
    result = described_class.call(id: game.id, confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
    expect(result.content.first[:text]).to include("no fields")
  end

  it "404s on missing game" do
    result = described_class.call(id: 999_999, notes: "x", confirm: "yes")
    expect(result.to_h[:isError]).to be(true)
  end

  it "rejects boolean confirm smuggling" do
    result = described_class.call(id: game.id, notes: "x", confirm: true)
    expect(result.to_h[:isError]).to be(true)
  end

  it "is gated on app scope" do
    record, _plaintext = ApiToken.generate!(
      user: User.first || create(:user),
      name: "dev-only", scopes: [ Scopes::DEV ]
    )
    Current.token = record
    result = described_class.call(id: game.id, notes: "x", confirm: "yes")
    expect(result.content.first[:text]).to include("insufficient_scope")
  end
end
