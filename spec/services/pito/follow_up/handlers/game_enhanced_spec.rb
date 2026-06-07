# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameEnhanced, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { create(:conversation) }
  let!(:game)        { create(:game, title: "Elden Ring") }
  let(:turn) do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#enh-1234 similar", position: 1
    )
  end

  def build_enhanced_event(payload_overrides = {})
    body = %(<div class="pito-game-enhanced-message"><p class="text-fg mb-2">Great import.</p></div>)
    base_payload = {
      "body"         => body,
      "html"         => true,
      "game_id"      => game.id,
      "reply_handle" => "enh-1234",
      "reply_target" => "game_enhanced"
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  it "registers for the game_enhanced target in :mutate mode" do
    expect(described_class.target).to eq("game_enhanced")
    expect(described_class.mode).to eq(:mutate)
  end

  # ── reindex ──────────────────────────────────────────────────────────────────

  describe "#call — reindex" do
    let(:source_event) { build_enhanced_event }

    subject(:result) do
      handler.call(event: source_event, rest: "reindex", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation with command game_reindex" do
      expect(result.events.first[:payload]["command"]).to eq("game_reindex")
    end

    it "carries game_id and game_title" do
      payload = result.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
      expect(payload["game_title"]).to eq("Elden Ring")
    end

    it "stamps the confirmation as followupable" do
      expect(result.events.first[:payload]["reply_target"]).to eq("confirmation")
    end
  end

  # ── similar (no filters) ─────────────────────────────────────────────────────

  describe "#call — similar" do
    let(:source_event) { build_enhanced_event }

    context "when recommendations are found" do
      let(:similar_game) { create(:game, title: "Sekiro") }
      let(:sim_result)   { Pito::Recommendations::Result.new(game: similar_game, score: 88, distance: 0.12) }

      before do
        allow(Pito::Recommendations).to receive(:similar_games).and_return([ sim_result ])
      end

      subject(:result) do
        handler.call(event: source_event, rest: "similar", conversation:)
      end

      it "returns a Result::Mutation" do
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end

      it "sets kind: system" do
        expect(result.kind).to eq("system")
      end

      it "includes the similar game title in body" do
        expect(result.payload["body"]).to include("Sekiro")
      end

      it "retains the original reply_handle" do
        expect(result.payload["reply_handle"]).to eq("enh-1234")
      end

      it "retains reply_target: game_enhanced" do
        expect(result.payload["reply_target"]).to eq("game_enhanced")
      end

      it "does NOT set reply_consumed (chainable)" do
        expect(result.payload["reply_consumed"]).to be_nil
      end

      it "carries game_id for future follow-ups" do
        expect(result.payload["game_id"]).to eq(game.id)
      end

      it "passes filters to similar_games" do
        handler.call(event: source_event, rest: "similar genre=action year=2022", conversation:)
        expect(Pito::Recommendations).to have_received(:similar_games)
          .with(game, filters: { genre: "action", year: "2022" })
      end
    end

    context "when no similar games are found" do
      before do
        allow(Pito::Recommendations).to receive(:similar_games).and_return([])
      end

      subject(:result) do
        handler.call(event: source_event, rest: "similar", conversation:)
      end

      it "returns a Result::Mutation with witty empty-state" do
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
        expect(result.payload["body"]).to include("Elden Ring")
      end
    end
  end

  # ── similar with filters ──────────────────────────────────────────────────────

  describe "filter parsing" do
    let(:source_event) { build_enhanced_event }

    it "parses key=value tokens correctly" do
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
      handler.call(event: source_event, rest: "similar genre=rpg score=70 ttb=long developer=fromsoft", conversation:)
      expect(Pito::Recommendations).to have_received(:similar_games)
        .with(game, filters: { genre: "rpg", score: "70", ttb: "long", developer: "fromsoft" })
    end

    it "maps 'complexity' as an alias for ttb" do
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
      handler.call(event: source_event, rest: "similar complexity=short", conversation:)
      expect(Pito::Recommendations).to have_received(:similar_games)
        .with(game, filters: { complexity: "short" })
    end

    it "ignores unknown filter keys" do
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
      handler.call(event: source_event, rest: "similar bogus=foo genre=action", conversation:)
      expect(Pito::Recommendations).to have_received(:similar_games)
        .with(game, filters: { genre: "action" })
    end
  end

  # ── channel ───────────────────────────────────────────────────────────────────

  describe "#call — channel" do
    let(:source_event) { build_enhanced_event }
    let(:connection)   { create(:youtube_connection) }
    let(:ch)           { create(:channel, handle: "@fromsoft", youtube_connection: connection) }
    let(:ch_result)    { Game::ChannelRecommendation::Result.new(channel: ch, score: 91, distance: 0.09) }

    context "when channel recommendations are found" do
      before do
        allow(Pito::Recommendations).to receive(:channels_for).and_return([ ch_result ])
      end

      subject(:result) do
        handler.call(event: source_event, rest: "channel", conversation:)
      end

      it "returns a Result::Mutation" do
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end

      it "includes the channel handle in body" do
        expect(result.payload["body"]).to include("@fromsoft")
      end

      it "retains reply_handle and reply_target (chainable)" do
        expect(result.payload["reply_handle"]).to eq("enh-1234")
        expect(result.payload["reply_target"]).to eq("game_enhanced")
      end

      it "does NOT consume the event" do
        expect(result.payload["reply_consumed"]).to be_nil
      end
    end

    context "when no channels are found" do
      before do
        allow(Pito::Recommendations).to receive(:channels_for).and_return([])
      end

      it "returns a mutation with witty empty text" do
        result = handler.call(event: source_event, rest: "channel", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
        expect(result.payload["body"]).to include("Elden Ring")
      end
    end
  end

  # ── chaining: similar then channel ───────────────────────────────────────────

  describe "chaining similar then channel" do
    it "replacing prior segment area with channel results" do
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
      allow(Pito::Recommendations).to receive(:channels_for).and_return([])

      source_event = build_enhanced_event
      # First call: similar (mutates body)
      sim_result = handler.call(event: source_event, rest: "similar", conversation:)
      # Simulate the event being updated with the mutation
      source_event.update!(payload: sim_result.payload)

      # Second call: channel (chains off the updated event)
      ch_result = handler.call(event: source_event, rest: "channel", conversation:)
      expect(ch_result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(ch_result.payload["reply_handle"]).to eq("enh-1234")
    end
  end

  # ── game_not_found ────────────────────────────────────────────────────────────

  describe "#call — game_id missing from payload" do
    it "returns a Result::Error" do
      event = build_enhanced_event("game_id" => nil)
      result = handler.call(event: event, rest: "similar", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_enhanced.errors.game_not_found")
    end
  end

  # ── unknown action ────────────────────────────────────────────────────────────

  describe "#call — unknown action" do
    let(:source_event) { build_enhanced_event }

    it "returns a Result::Error" do
      result = handler.call(event: source_event, rest: "bogus", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_enhanced.errors.invalid_action")
    end
  end

  # ── registry ─────────────────────────────────────────────────────────────────

  describe "registry" do
    before { Pito::FollowUp::Registry.register(described_class) }

    it "is registered under 'game_enhanced'" do
      expect(Pito::FollowUp::Registry.for("game_enhanced")).to eq(described_class)
    end

    it "has mode :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("game_enhanced")).to eq(:mutate)
    end
  end
end
