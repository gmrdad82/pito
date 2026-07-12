# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::ImportAnnounce do
  let(:game) { create(:game, title: "Rayman: 30th Anniversary Edition") }

  # ── :import — present-tense status, no id, inline timestamp (19.2) ────────────
  describe ".call with action: :import" do
    subject(:payload) { described_class.call(game, action: :import) }

    let(:body) { payload["body"] }

    it "says 'importing' (present tense), not 'imported'" do
      expect(body).to include("importing")
      expect(body).not_to include("imported")
    end

    it "does NOT show the game #id" do
      expect(body).not_to include("##{game.id}")
    end

    it "puts the timestamp inline via the ts-slot (same row as the copy)" do
      expect(body).to include("data-pito-ts-slot")
    end

    it "shimmers the title as the subject" do
      expect(body).to include("pito-subject-shimmer")
    end

    it "still stamps the game_id in the payload (not shown, used for anchoring)" do
      expect(payload["game_id"]).to eq(game.id)
    end
  end

  # ── :resync — unchanged: 're-synced' + id ────────────────────────────────────
  describe ".call with action: :resync" do
    subject(:payload) { described_class.call(game, action: :resync) }

    let(:body) { payload["body"] }

    it "says 're-synced' and shows the #id" do
      expect(body).to include("re-synced")
      expect(body).to include("##{game.id}")
    end

    it "puts the timestamp inline via the ts-slot" do
      expect(body).to include("data-pito-ts-slot")
    end
  end
end
