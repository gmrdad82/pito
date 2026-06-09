# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::TargetResolution, type: :model do
  # A throwaway verb handler — the module is mixed into Pito::Chat::Handler.
  let(:handler_class) do
    Class.new(Pito::Chat::Handler) do
      self.verb = :test
      self.description_key = "pito.chat.test.descriptions.test"
      def call = Pito::Chat::Result::Ok.new(events: [])
    end
  end

  let(:noun) { %w[game games] }

  def free_chat(raw)
    handler_class.new(message: instance_double(Pito::Chat::Message, raw: raw), conversation: nil)
  end

  def follow_up(payload:, rest:)
    ctx = Pito::Chat::FollowUpContext.new(
      source_event: instance_double(Event, payload: payload),
      rest:         rest
    )
    handler_class.new(message: instance_double(Pito::Chat::Message), conversation: nil, follow_up: ctx)
  end

  def resolve(handler)
    handler.resolve_target(::Game, id_key: :game_id, noun_fillers: noun)
  end

  # ── free-chat: typed ref ────────────────────────────────────────────────────
  describe "free-chat" do
    let!(:game) { create(:game, title: "Dead Space") }

    it "resolves by id (with or without #)" do
      expect(resolve(free_chat("show game ##{game.id}"))).to eq(game)
      expect(resolve(free_chat("show game #{game.id}"))).to eq(game)
    end

    it "resolves by title (case-insensitive)" do
      expect(resolve(free_chat("show game dead space"))).to eq(game)
    end

    it "returns :needs_ref when no reference is typed" do
      expect(resolve(free_chat("show game"))).to eq(:needs_ref)
      expect(resolve(free_chat("show"))).to eq(:needs_ref)
    end

    it "returns nil for an unknown reference" do
      expect(resolve(free_chat("show game 999999"))).to be_nil
    end
  end

  # ── detail reply: the card's entity, no ref ─────────────────────────────────
  describe "detail context" do
    let!(:game) { create(:game, title: "Pragmata") }

    it "resolves the source card's entity from its game_id (ignores rest)" do
      handler = follow_up(payload: { "game_id" => game.id }, rest: "")
      expect(resolve(handler)).to eq(game)
    end

    it "returns nil when the stamped entity no longer exists" do
      handler = follow_up(payload: { "game_id" => 999_999 }, rest: "")
      expect(resolve(handler)).to be_nil
    end
  end

  # ── list reply: typed ref scoped to the list's rows ─────────────────────────
  describe "list context (scoped to the list's rows)" do
    let!(:shown)  { create(:game, title: "Scars Above") }
    let!(:hidden) { create(:game, title: "Mad Max") }

    # A kv-table list payload whose only row is `shown` (#id in the first cell).
    let(:payload) do
      { "table_rows" => [ { cells: [ { text: "##{shown.id}" }, { text: shown.title } ] } ] }
    end

    it "resolves a row that IS in the list (by id)" do
      expect(resolve(follow_up(payload:, rest: shown.id.to_s))).to eq(shown)
    end

    it "resolves a row that IS in the list (by title)" do
      expect(resolve(follow_up(payload:, rest: "scars above"))).to eq(shown)
    end

    it "does NOT resolve a real game that is not in the list" do
      expect(resolve(follow_up(payload:, rest: hidden.id.to_s))).to be_nil
    end

    it "returns :needs_ref when the reply carries no reference" do
      expect(resolve(follow_up(payload:, rest: ""))).to eq(:needs_ref)
    end
  end
end
