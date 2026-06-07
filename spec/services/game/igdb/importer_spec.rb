# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Igdb::Importer, type: :service do
  before { allow(GameIgdbSync).to receive(:perform_later) }

  context "when the game is not in the Library" do
    it "creates a stub and reports :import" do
      result = nil
      expect { result = described_class.call(igdb_id: 1020, title: "Lies of P") }
        .to change(Game, :count).by(1)
      expect(result[:action]).to eq(:import)
      expect(result[:game].igdb_id).to eq(1020)
      expect(result[:game].title).to eq("Lies of P")
      expect(GameIgdbSync).to have_received(:perform_later).with(result[:game].id)
    end

    it "falls back to the default title when none is given" do
      result = described_class.call(igdb_id: 7)
      expect(result[:game].title).to eq("Untitled game")
    end
  end

  context "when the game is already in the Library" do
    let!(:existing) { create(:game, igdb_id: 1020, title: "Lies of P") }

    it "does not duplicate and reports :resync" do
      result = nil
      expect { result = described_class.call(igdb_id: 1020, title: "Lies of P") }
        .not_to change(Game, :count)
      expect(result[:action]).to eq(:resync)
      expect(result[:game]).to eq(existing)
      expect(GameIgdbSync).to have_received(:perform_later).with(existing.id)
    end
  end
end
