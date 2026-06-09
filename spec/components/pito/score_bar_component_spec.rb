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

  describe "FILL_CELLS" do
    it "emits more = than can fit (full-width bar, CSS-clipped)" do
      expect(described_class::FILL_CELLS).to be >= 100
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

    it "is the precise score percent (no cell snapping)" do
      expect(described_class.new(score: 50).overlay_left_percent).to eq(50.0)
      expect(described_class.new(score: 81).overlay_left_percent).to eq(81.0)
      expect(described_class.new(score: 92).overlay_left_percent).to eq(92.0)
    end

    it "clamps to 0..100" do
      expect(described_class.new(score: 100).overlay_left_percent).to eq(100.0)
      expect(described_class.new(score: 0).overlay_left_percent).to eq(0.0)
    end
  end

  describe "#fill_text" do
    it "returns FILL_CELLS = characters (overflow, CSS-clipped to full width)" do
      comp = described_class.new
      expect(comp.fill_text).to eq("=" * described_class::FILL_CELLS)
    end
  end

  describe "#score_label" do
    it "returns a non-empty witty label via Pito::Copy" do
      expect(described_class.new(score: 80).score_label).to be_a(String).and be_present
    end
  end

  describe "render_inline — gradient structure" do
    it "renders the pito-score-bar__fill element" do
      comp = described_class.new(score: 75)
      html = render_inline(comp).to_html
      expect(html).to include("pito-score-bar__fill")
    end

    # The heat gradient lives in `.pito-score-bar__fill` CSS (application.css),
    # not inline on the element, so the rendered HTML only carries the class.
    # The theme-var sourcing of the gradient stops is asserted against the
    # stylesheet directly below.
  end

  describe "heat gradient (application.css) — theme-aware stops" do
    let(:css) do
      Rails.root.join("app/assets/tailwind/application.css").read
    end

    let(:fill_rule) do
      # Isolate the `.pito-score-bar__fill { … }` declaration block.
      css[/\.pito-score-bar__fill\s*\{.*?\}/m]
    end

    it "sources stops from theme accent vars" do
      %w[--accent-red --accent-orange --accent-yellow --accent-green].each do |token|
        expect(fill_rule).to include("var(#{token})")
      end
    end

    it "mixes every stop toward --fg-default for theme-adaptive contrast (T17.1)" do
      # The fg-mix darkens stops on light themes and lightens them on dark
      # themes, so the worst-case stop (yellow 'fair') rises from ~1.62:1 to
      # ~2.56:1 across all 18 themes. See Plan P17 / the OKLab+WCAG sweep.
      expect(fill_rule).to include("var(--fg-default)")
    end

    it "uses color-mix(in oklch) for both the hue blends and the fg-mix" do
      expect(fill_rule).to include("color-mix(in oklch")
      # Most stops are a single fg-mix color-mix; the poor + good stops nest a
      # second hue-blend color-mix inside. (The very-bad stops are now a single
      # mix toward --fg-faded so the worst end is the DARKEST red.) 12 total.
      expect(fill_rule.scan("color-mix(in oklch").size).to eq(12)
    end

    it "keeps the revive tier breakpoints (25/50/65/75/85/90%)" do
      %w[25% 50% 65% 75% 85% 90% 100%].each do |pct|
        expect(fill_rule).to include(pct)
      end
    end

    it "contains no literal hex colors in the gradient" do
      expect(fill_rule).not_to match(/#[0-9a-fA-F]{3,8}\b/)
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

    it "sets data-tier=missing on the muted bar when score is nil" do
      node = render_inline(described_class.new)
      bar  = node.css("[data-tier='missing']")
      expect(bar).not_to be_empty
    end

    it "sets the correct data-tier for each score tier boundary" do
      {
        95 => "excellent",
        85 => "good",
        75 => "fair",
        65 => "meh",
        55 => "poor",
        30 => "bad",
        10 => "very_bad"
      }.each do |score, tier|
        node = render_inline(described_class.new(score:))
        bar  = node.css("[data-tier='#{tier}']")
        expect(bar).not_to be_empty, "expected data-tier=#{tier} for score #{score}"
      end
    end

    it "sets data-score on the bar element" do
      node = render_inline(described_class.new(score: 82))
      bar  = node.css("[data-score='82']")
      expect(bar).not_to be_empty
    end

    it "positions the bubble + needle at the precise score percent (left: N%)" do
      node = render_inline(described_class.new(score: 81))
      html = node.to_html
      expect(html).to include("left: 81.0%")
    end
  end

  describe "label + full-width structure" do
    it "renders the witty label before the track" do
      node = render_inline(described_class.new(score: 80))
      expect(node.css(".pito-score-bar__label").text).to be_present
    end

    it "renders the label by default (show_label omitted)" do
      node = render_inline(described_class.new(score: 80))
      expect(node.css(".pito-score-bar__label")).not_to be_empty
    end

    it "omits the label when show_label: false (recommendation surfaces)" do
      node = render_inline(described_class.new(score: 80, show_label: false))
      expect(node.css(".pito-score-bar__label")).to be_empty
      # The bar itself still renders.
      expect(node.css(".pito-score-bar")).not_to be_empty
    end

    it "places the tick inside the track so its left:% maps across the bar" do
      node = render_inline(described_class.new(score: 81))
      tick = node.css(".pito-score-bar__track .pito-score-bar__tick").first
      expect(tick).not_to be_nil
    end
  end
end
