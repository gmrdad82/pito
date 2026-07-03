# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Dispatch::Predicates do
  # ── registry contents ──────────────────────────────────────────────────────────

  describe ".names" do
    it "returns a frozen Array of strings" do
      expect(described_class.names).to be_a(Array).and be_frozen
      expect(described_class.names).to all(be_a(String))
    end

    it "includes the three named emit_if predicates" do
      expect(described_class.names).to include("has_any_videos", "has_linked_game", "has_linked_videos")
    end
  end

  describe ".get" do
    it "returns a callable lambda for a known predicate" do
      pred = described_class.get("has_any_videos")
      expect(pred).to respond_to(:call)
    end

    it "returns nil for an unknown predicate name" do
      expect(described_class.get("nonexistent")).to be_nil
    end

    it "returns nil when name is nil" do
      expect(described_class.get(nil)).to be_nil
    end
  end

  # ── predicate behaviour ────────────────────────────────────────────────────────

  describe "has_any_videos" do
    let(:pred) { described_class.get("has_any_videos") }

    it "returns true when entity.videos.any? is true" do
      entity = double("channel", videos: double(any?: true))
      expect(pred.call(entity)).to be(true)
    end

    it "returns false when entity.videos.any? is false" do
      entity = double("channel", videos: double(any?: false))
      expect(pred.call(entity)).to be(false)
    end
  end

  describe "has_linked_game" do
    let(:pred) { described_class.get("has_linked_game") }

    it "returns truthy when entity.linked_games.first is present" do
      entity = double("vid", linked_games: double(first: "a-game"))
      expect(pred.call(entity)).to be_truthy
    end

    it "returns falsy when entity.linked_games.first is nil" do
      entity = double("vid", linked_games: double(first: nil))
      expect(pred.call(entity)).to be_falsy
    end
  end

  describe "has_linked_videos" do
    let(:pred) { described_class.get("has_linked_videos") }

    it "returns true when entity.linked_videos.any? is true" do
      entity = double("game", linked_videos: double(any?: true))
      expect(pred.call(entity)).to be(true)
    end

    it "returns false when entity.linked_videos.any? is false" do
      entity = double("game", linked_videos: double(any?: false))
      expect(pred.call(entity)).to be(false)
    end
  end

  # ── schema wire-up ─────────────────────────────────────────────────────────────

  describe "Schema::PREDICATES re-points at this registry" do
    it "Schema::PREDICATES equals Predicates.names" do
      expect(Pito::Dispatch::Schema::PREDICATES).to eq(described_class.names)
    end
  end
end
