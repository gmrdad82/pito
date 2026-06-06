# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ScoreBarComponent do
  let(:game) { build_stubbed(:game, igdb_rating: 87.0, igdb_rating_count: 150) }

  describe ".synthesized_score" do
    subject(:score) { described_class.synthesized_score(game) }

    it "reads from game.score (via ScoreCalculator)" do
      expect(score).to eq(87)
    end

    context "when game is nil" do
      let(:game) { nil }

      it { is_expected.to be_nil }
    end

    context "when no rating triplet has a positive count" do
      let(:game) { build_stubbed(:game, igdb_rating: 80, igdb_rating_count: 0) }

      it { is_expected.to eq(0) }
    end
  end

  describe ".tier_for" do
    {
      nil  => "missing",
      100  => "excellent",
      90   => "excellent",
      89   => "good",
      80   => "good",
      79   => "fair",
      70   => "fair",
      69   => "meh",
      60   => "meh",
      59   => "poor",
      50   => "poor",
      49   => "bad",
      25   => "bad",
      24   => "very_bad",
      0    => "very_bad"
    }.each do |input, expected|
      it "maps #{input.inspect} -> #{expected}" do
        expect(described_class.tier_for(input)).to eq(expected)
      end
    end
  end

  describe "BAR_CELLS" do
    it "is 60" do
      expect(described_class::BAR_CELLS).to eq(60)
    end
  end

  describe "#score" do
    context "with an explicit override" do
      it "returns the override" do
        comp = described_class.new(score: 77)
        expect(comp.score).to eq(77)
      end
    end

    context "with a game" do
      it "reads the synthesized score" do
        comp = described_class.new(game: game)
        expect(comp.score).to eq(87)
      end
    end
  end

  describe "#overlay?" do
    it "is false when score is nil" do
      comp = described_class.new
      expect(comp.overlay?).to be false
    end

    it "is true when score present" do
      comp = described_class.new(game: game)
      expect(comp.overlay?).to be true
    end
  end

  describe "#overlay_left_percent" do
    it "returns nil when score is nil" do
      comp = described_class.new
      expect(comp.overlay_left_percent).to be_nil
    end

    it "clamps the score to 0..100" do
      comp = described_class.new(score: 50)
      expect(comp.overlay_left_percent).to eq(50.0)
    end
  end

  describe "#fill_text" do
    it "returns 60 = characters" do
      comp = described_class.new
      expect(comp.fill_text).to eq("=" * 60)
    end
  end

  describe "render_inline — gradient structure" do
    it "renders the pito-score-bar__fill element" do
      comp = described_class.new(score: 75)
      html = render_inline(comp).to_html
      expect(html).to include("pito-score-bar__fill")
    end

    it "renders the tick and bubble when score is present" do
      comp = described_class.new(score: 75)
      html = render_inline(comp).to_html
      expect(html).to include("pito-score-bar__tick")
      expect(html).to include("pito-score-bar__bubble")
    end

    it "renders the muted variant when score is nil and not resyncing" do
      comp = described_class.new
      html = render_inline(comp).to_html
      expect(html).to include("pito-score-bar--muted")
      expect(html).not_to include("pito-score-bar__tick")
    end

    it "includes the score value in the bubble" do
      comp = described_class.new(score: 87)
      html = render_inline(comp).to_html
      expect(html).to include("87")
    end
  end
end
