# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::EnhancedSegments do
  let(:conversation) { create(:conversation) }
  let(:turn) do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#enh-1234 similar", position: 1
    )
  end
  let!(:game) { create(:game, title: "Elden Ring") }

  def build_enhanced_event(payload_overrides = {})
    body = %(<div class="pito-game-enhanced-message"><p class="text-fg mb-2">Great import.</p></div>)
    base_payload = {
      "body"    => body,
      "html"    => true,
      "game_id" => game.id
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  describe ".call with similar results" do
    let(:similar_game) { create(:game, title: "Sekiro") }
    let(:sim_result)   { Pito::Recommendation::GameSimilarity::Result.new(game: similar_game, score: 88, breakdown: nil) }
    let(:event)        { build_enhanced_event }

    subject(:payload) do
      described_class.call(
        event: event, game: game, results: [ sim_result ],
        result_type: :similar, original_handle: "enh-1234"
      )
    end

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes the similar game title in body" do
      expect(payload["body"]).to include("Sekiro")
    end

    it "includes the pito-game-enhanced-row class in body" do
      expect(payload["body"]).to include("pito-game-enhanced-row")
    end

    it "does NOT set reply_handle" do
      expect(payload["reply_handle"]).to be_nil
    end

    it "does NOT set reply_target" do
      expect(payload["reply_target"]).to be_nil
    end

    it "does NOT set reply_consumed" do
      expect(payload["reply_consumed"]).to be_nil
    end

    it "carries game_id" do
      expect(payload["game_id"]).to eq(game.id)
    end

    it "preserves the intro paragraph from the original event" do
      expect(payload["body"]).to include("Great import.")
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end

  describe ".call with channel results" do
    let(:connection) { create(:youtube_connection) }
    let(:channel)    { create(:channel, handle: "@fromsoft", youtube_connection: connection) }
    let(:ch_result)  { Game::ChannelRecommendation::Result.new(channel: channel, score: 91, breakdown: nil) }
    let(:event)      { build_enhanced_event }

    subject(:payload) do
      described_class.call(
        event: event, game: game, results: [ ch_result ],
        result_type: :channel, original_handle: "enh-1234"
      )
    end

    it "includes the channel handle in body" do
      expect(payload["body"]).to include("@fromsoft")
    end

    it "does NOT set reply_handle or reply_target" do
      expect(payload["reply_handle"]).to be_nil
      expect(payload["reply_target"]).to be_nil
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end

  describe ".call with empty results" do
    let(:event) { build_enhanced_event }

    it "includes the empty-state div for similar" do
      payload = described_class.call(
        event: event, game: game, results: [],
        result_type: :similar, original_handle: "enh-1234"
      )
      expect(payload["body"]).to include("pito-game-enhanced-empty")
      expect(payload["body"]).to include("Elden Ring")
    end

    it "includes the empty-state div for channel" do
      payload = described_class.call(
        event: event, game: game, results: [],
        result_type: :channel, original_handle: "enh-1234"
      )
      expect(payload["body"]).to include("pito-game-enhanced-empty")
      expect(payload["body"]).to include("Elden Ring")
    end
  end
end
