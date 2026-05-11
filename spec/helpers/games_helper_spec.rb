require "rails_helper"

# Phase 27 — game tile metadata helpers.
#
# Three helpers cover the tile / list rating + meta surfaces:
#
#   * `format_game_rating(rating)` — zero-pads a numeric rating to a
#     minimum of two digits; returns `""` for nil so callers can
#     interpolate without conditional guards.
#   * `game_rating_display(game)` — legacy `<NN>/100` builder; kept
#     for back-compat. New visual surfaces use the colored bold badge
#     `Games::RatingBadgeComponent` instead.
#   * `game_meta_line(game)` — composes the tile's plain-text second
#     line `<NN> · <YYYY>`. Used as the tile's `title=` attribute
#     (screen readers + tooltip-on-truncation). The visual tile renders
#     the colored badge for the rating segment; this helper is the
#     inert text fallback.
#
# 2026-05-11 polish (Fix 2): `game_meta_line` dropped the `/100`
# suffix — the rating segment is now the bare integer.
RSpec.describe GamesHelper, type: :helper do
  describe "#format_game_rating" do
    it "returns \"\" for nil" do
      expect(helper.format_game_rating(nil)).to eq("")
    end

    it "zero-pads single-digit values — 5 → \"05\"" do
      expect(helper.format_game_rating(5)).to eq("05")
    end

    it "leaves two-digit values intact — 93 → \"93\"" do
      expect(helper.format_game_rating(93)).to eq("93")
    end

    it "does NOT truncate three-digit values — 100 → \"100\"" do
      # The zero-pad is a minimum-width contract, not a fixed width.
      expect(helper.format_game_rating(100)).to eq("100")
    end

    it "rounds (floors) decimal ratings via to_i — 8.7 → \"08\"" do
      expect(helper.format_game_rating(8.7)).to eq("08")
    end

    it "handles zero — 0 → \"00\"" do
      expect(helper.format_game_rating(0)).to eq("00")
    end

    it "handles BigDecimal ratings — BigDecimal('90.50') → \"90\"" do
      expect(helper.format_game_rating(BigDecimal("90.50"))).to eq("90")
    end
  end

  describe "#game_rating_display (legacy /100 string)" do
    it "returns \"\" for a game whose igdb_rating is nil" do
      g = build_stubbed(:game, igdb_rating: nil)
      expect(helper.game_rating_display(g)).to eq("")
    end

    it "renders the rating as <NN>/100" do
      g = build_stubbed(:game, igdb_rating: 88)
      expect(helper.game_rating_display(g)).to eq("88/100")
    end

    it "coerces decimal ratings via to_i (no zero-padding here)" do
      # The /100 surface uses integer-out-of-100 — small ratings
      # render as `5/100`, NOT `05/100`. Zero-padding belongs to the
      # legacy `format_game_rating` helper only.
      g = build_stubbed(:game, igdb_rating: 5)
      expect(helper.game_rating_display(g)).to eq("5/100")
    end

    it "does NOT include the star glyph (Fix 5 — retired in this polish)" do
      g = build_stubbed(:game, igdb_rating: 93)
      expect(helper.game_rating_display(g)).not_to include("★")
    end

    it "handles three-digit ratings — 100 → \"100/100\"" do
      g = build_stubbed(:game, igdb_rating: 100)
      expect(helper.game_rating_display(g)).to eq("100/100")
    end
  end

  describe "#game_meta_line (post Fix 2 — no /100 suffix)" do
    let(:both) do
      build_stubbed(:game, igdb_rating: 93, release_year: 2018)
    end

    let(:rating_only) do
      build_stubbed(:game, igdb_rating: 93, release_year: nil)
    end

    let(:year_only) do
      build_stubbed(:game, igdb_rating: nil, release_year: 2018)
    end

    let(:neither) do
      build_stubbed(:game, igdb_rating: nil, release_year: nil)
    end

    it "renders both pieces in rating-dot-year order with no /100 suffix" do
      # 2026-05-11 polish (Fix 2) — `/100` retired. The plain-text
      # composition is `<NN> · <YYYY>`; the colored badge is rendered
      # by the visual component, not this helper.
      expect(helper.game_meta_line(both)).to eq("93 · 2018")
    end

    it "does NOT zero-pad single-digit ratings — 5 → \"5 · 2018\"" do
      g = build_stubbed(:game, igdb_rating: 5, release_year: 2018)
      expect(helper.game_meta_line(g)).to eq("5 · 2018")
    end

    it "omits the year when release_year is nil" do
      expect(helper.game_meta_line(rating_only)).to eq("93")
    end

    it "omits the rating when igdb_rating is nil" do
      expect(helper.game_meta_line(year_only)).to eq("2018")
    end

    it "returns an empty string when both are nil" do
      expect(helper.game_meta_line(neither)).to eq("")
    end

    it "drops empty rating without leaving a leading dot" do
      line = helper.game_meta_line(year_only)
      expect(line).not_to start_with(" ")
      expect(line).not_to start_with("·")
    end

    it "drops empty year without leaving a trailing dot" do
      line = helper.game_meta_line(rating_only)
      expect(line).not_to end_with(" ")
      expect(line).not_to end_with("·")
    end

    it "does NOT include the star glyph (Fix 5 — retired)" do
      expect(helper.game_meta_line(both)).not_to include("★")
    end

    it "does NOT include the /100 suffix (Fix 2 — retired)" do
      expect(helper.game_meta_line(both)).not_to include("/100")
      expect(helper.game_meta_line(rating_only)).not_to include("/100")
    end

    it "uses the middle-dot separator (U+00B7) when both pieces are present" do
      expect(helper.game_meta_line(both)).to include("·")
    end

    it "does NOT include the middle-dot when only one piece renders" do
      expect(helper.game_meta_line(rating_only)).not_to include("·")
      expect(helper.game_meta_line(year_only)).not_to include("·")
    end
  end
end
