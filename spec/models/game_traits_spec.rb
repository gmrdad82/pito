# frozen_string_literal: true

require "rails_helper"

# ── Game traits — model integration (games.traits jsonb) ────────────────
#
# The validator LOGIC itself (every rule of what makes a traits hash legal)
# is exhaustively covered in spec/services/game/traits/vocabulary_spec.rb —
# this spec only proves the model wires that validator in correctly and that
# the four thin accessors (traits-design.md section 2) read the shape right.
RSpec.describe Game, type: :model do
  describe "traits jsonb default" do
    it "defaults to {} on a new record (never nil)" do
      expect(described_class.new.traits).to eq({})
    end

    it "defaults to {} on a persisted record" do
      game = create(:game)
      expect(game.reload.traits).to eq({})
    end
  end

  describe "traits validation" do
    it "is valid with {} (unclassified)" do
      game = build(:game, traits: {})
      expect(game).to be_valid
    end

    it "is valid with a well-formed traits hash" do
      game = build(:game, :with_traits)
      expect(game).to be_valid
    end

    it "is invalid with an unknown scale value, surfacing Vocabulary's message on :traits" do
      game = build(:game, traits: {
        "schema_version" => 1,
        "values" => { "difficulty" => "impossible" }
      })

      expect(game).not_to be_valid
      expect(game.errors[:traits]).to include(a_string_matching(/not a valid value for scale "difficulty"/))
    end

    it "is invalid with an unsupported schema_version" do
      game = build(:game, traits: { "schema_version" => 99, "values" => {} })

      expect(game).not_to be_valid
      expect(game.errors[:traits]).to include(a_string_matching(/unsupported schema_version 99/))
    end

    it "rejects save (not just .valid?) via ActiveRecord::RecordInvalid" do
      game = build(:game, traits: { "schema_version" => 1, "values" => { "difficulty" => "impossible" } })
      expect { game.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "accessors on an unclassified game" do
    subject(:game) { build(:game, traits: {}) }

    it "#trait_scales is {}" do
      expect(game.trait_scales).to eq({})
    end

    it "#trait_tags is []" do
      expect(game.trait_tags).to eq([])
    end

    it "#trait_value returns nil for a declared scale name" do
      expect(game.trait_value("difficulty")).to be_nil
    end

    it "#trait_value returns false for a declared tag name" do
      expect(game.trait_value("skill_based")).to be false
    end

    it "#trait_value returns nil for an undeclared name (never raises)" do
      expect(game.trait_value("not_a_real_trait")).to be_nil
    end

    it "#trait_source returns nil for any name" do
      expect(game.trait_source("difficulty")).to be_nil
      expect(game.trait_source("skill_based")).to be_nil
    end
  end

  describe "accessors on a classified game (factory :with_traits)" do
    subject(:game) { build(:game, :with_traits) }

    it "#trait_scales returns the set scale values, keyed by name" do
      expect(game.trait_scales).to eq("difficulty" => "brutal", "story" => "catching")
    end

    it "#trait_tags returns the set tags in declaration order" do
      expect(game.trait_tags).to eq(%w[skill_based worth_it action])
    end

    it "#trait_value resolves a set scale to its value" do
      expect(game.trait_value("difficulty")).to eq("brutal")
    end

    it "#trait_value resolves an unset declared scale to nil" do
      expect(game.trait_value("pace")).to be_nil
    end

    it "#trait_value resolves a set tag to true" do
      expect(game.trait_value("skill_based")).to be true
    end

    it "#trait_value resolves an unset declared tag to false" do
      expect(game.trait_value("flight")).to be false
    end

    it "#trait_source reports the classified source" do
      expect(game.trait_source("difficulty")).to eq("classified")
    end

    it "#trait_source reports the owner source (including an owner-overridden but present value)" do
      expect(game.trait_source("story")).to eq("owner")
    end

    it "#trait_source reports the derived source for a derived tag" do
      expect(game.trait_source("action")).to eq("derived")
    end

    it "#trait_source reports \"owner\" for an owner-pinned-absent tag not present in trait_tags" do
      expect(game.trait_tags).not_to include("war")
      expect(game.trait_source("war")).to eq("owner")
    end

    it "#trait_source returns nil for a name with no sources entry" do
      expect(game.trait_source("game_of_the_year")).to be_nil
    end
  end
end
