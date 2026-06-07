# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::SimilarGames, type: :service do
  # Build a 1024-dim unit vector with a single hot dimension so cosine
  # distances are predictable.
  def vec(index, value: 1.0)
    Array.new(1024, 0.0).tap { |a| a[index] = value }
  end

  let(:game) { create(:game, title: "Lies of P") }

  before { game.update_column(:summary_embedding, vec(0)) }

  it "returns Game.none for a nil game" do
    expect(described_class.call(nil)).to eq(Game.none)
  end

  it "returns Game.none when the game has no embedding" do
    game.update_column(:summary_embedding, nil)
    expect(described_class.call(game)).to eq(Game.none)
  end

  it "excludes the input game from the results" do
    create(:game, title: "Other").update_column(:summary_embedding, vec(0))
    expect(described_class.call(game).to_a).not_to include(game)
  end

  it "orders neighbors by ascending cosine distance" do
    near = create(:game, title: "Bloodborne")
    near.update_column(:summary_embedding, vec(0, value: 0.99))
    far = create(:game, title: "Stardew Valley")
    far.update_column(:summary_embedding, vec(1))

    expect(described_class.call(game).to_a).to eq([ near, far ])
  end

  it "honours the limit" do
    3.times { |i| create(:game).update_column(:summary_embedding, vec(0, value: 0.5 + i * 0.1)) }
    expect(described_class.call(game, limit: 2).to_a.size).to eq(2)
  end
end
