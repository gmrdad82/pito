require "rails_helper"

# 2026-05-11 polish (Fix 2) — colored bold rating badge.
#
# Renders an IGDB rating as a bold `<span>` whose color tracks six
# discrete tiers. The legacy `<NN>/100` literal is gone — the badge
# emits the integer rating only, sourcing color from a per-tier
# `--color-rating-*` CSS variable.
RSpec.describe Games::RatingBadgeComponent, type: :component do
  def render_rating(value)
    render_inline(described_class.new(rating: value))
  end

  describe "tier resolution — boundary inclusive lower bounds" do
    {
      100 => "excellent",
       95 => "excellent",
       90 => "excellent",
       89 => "good",
       80 => "good",
       79 => "fair",
       70 => "fair",
       69 => "meh",
       60 => "meh",
       59 => "poor",
       50 => "poor",
       49 => "bad",
       25 => "bad",
        0 => "bad"
    }.each do |value, expected_tier|
      it "maps #{value} to tier `#{expected_tier}`" do
        render_rating(value)
        expect(page).to have_css("span.game-rating-badge--#{expected_tier}")
        expect(page).to have_css("span[data-tier='#{expected_tier}']")
      end
    end
  end

  describe "happy path — rendered shape" do
    it "renders the integer rating with no `/100` suffix" do
      render_rating(88)
      expect(page).to have_css("span.game-rating-badge", text: "88")
      expect(rendered_content).not_to include("/100")
      expect(rendered_content).not_to include("/ 100")
    end

    it "applies font-weight: bold via inline style" do
      render_rating(88)
      span = page.find("span.game-rating-badge")
      expect(span[:style]).to include("font-weight: bold")
    end

    it "applies the per-tier color via the --color-rating-* variable" do
      render_rating(95)
      span = page.find("span.game-rating-badge--excellent")
      expect(span[:style]).to include("color: var(--color-rating-excellent)")
    end

    it "stamps data-rating with the integer value (decimal coerced via to_i)" do
      render_rating(BigDecimal("88.75"))
      span = page.find("span.game-rating-badge")
      expect(span["data-rating"]).to eq("88")
    end

    it "drops the star glyph (Fix 5 — retired app-wide)" do
      render_rating(93)
      expect(rendered_content).not_to include("★")
    end
  end

  describe "missing rating — nil + blank coerce to em-dash" do
    it "renders a muted em-dash for nil" do
      render_rating(nil)
      expect(page).to have_css("span.game-rating-badge--missing.text-muted", text: "—")
    end

    it "renders a muted em-dash for an empty string" do
      render_rating("")
      expect(page).to have_css("span.game-rating-badge--missing", text: "—")
    end

    it "does NOT apply a color style on the missing-rating span" do
      render_rating(nil)
      span = page.find("span.game-rating-badge--missing")
      expect(span[:style].to_s).not_to include("color:")
    end

    it "stamps data-tier=missing on the missing span" do
      render_rating(nil)
      expect(page).to have_css("span[data-tier='missing']")
    end
  end

  describe "decimal / BigDecimal coercion" do
    it "floors decimals via to_i — 89.99 → tier `good` (not excellent)" do
      render_rating(89.99)
      expect(page).to have_css("span.game-rating-badge--good")
      expect(page).not_to have_css("span.game-rating-badge--excellent")
    end

    it "treats BigDecimal('90.00') as excellent (boundary inclusive)" do
      render_rating(BigDecimal("90.00"))
      expect(page).to have_css("span.game-rating-badge--excellent")
    end
  end

  describe "css_color helper" do
    it "returns the var() expression for the resolved tier" do
      component = described_class.new(rating: 72)
      expect(component.css_color).to eq("var(--color-rating-fair)")
    end

    it "still returns the bad-tier color for ratings well below 50" do
      component = described_class.new(rating: 10)
      expect(component.css_color).to eq("var(--color-rating-bad)")
    end
  end

  describe "flaws" do
    it "does NOT render `/100` anywhere in the output" do
      render_rating(75)
      expect(rendered_content).not_to match(%r{/\s*100})
    end

    it "does NOT render the rating in a non-bold form" do
      render_rating(60)
      span = page.find("span.game-rating-badge")
      expect(span[:style]).to include("font-weight: bold")
    end
  end
end
