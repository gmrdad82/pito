require "rails_helper"

# Phase 27 — game tile metadata helpers.
#
# Two helpers cover the tile's second-line layout:
#
#   * `format_game_rating(rating)` — zero-pads a numeric rating to a
#     minimum of two digits; returns `""` for nil so callers can
#     interpolate without conditional guards.
#   * `game_meta_line(game)` — composes the second line
#     `★ <RR> · <YYYY>`, dropping pieces when rating / year are
#     missing.
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
      # IGDB ratings are decimals in storage. `.to_i` floors; existing
      # tile copy already used `.to_i` before this refactor, so we
      # preserve the same coercion semantics.
      expect(helper.format_game_rating(8.7)).to eq("08")
    end

    it "handles zero — 0 → \"00\"" do
      expect(helper.format_game_rating(0)).to eq("00")
    end

    it "handles BigDecimal ratings — BigDecimal('90.50') → \"90\"" do
      expect(helper.format_game_rating(BigDecimal("90.50"))).to eq("90")
    end
  end

  describe "#game_meta_line" do
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

    it "renders both pieces in star-rating-dot-year order" do
      # Locked layout: rating FIRST, then year — reversed from the
      # pre-Phase-27 caption "(2018) ★ 93".
      expect(helper.game_meta_line(both)).to eq("★ 93 · 2018")
    end

    it "zero-pads single-digit ratings inside the line — 5 → \"05\"" do
      g = build_stubbed(:game, igdb_rating: 5, release_year: 2018)
      expect(helper.game_meta_line(g)).to eq("★ 05 · 2018")
    end

    it "omits the year when release_year is nil" do
      expect(helper.game_meta_line(rating_only)).to eq("★ 93")
    end

    it "omits the rating when igdb_rating is nil" do
      expect(helper.game_meta_line(year_only)).to eq("2018")
    end

    it "returns an empty string when both are nil" do
      expect(helper.game_meta_line(neither)).to eq("")
    end

    it "drops empty rating without leaving a leading dot/star" do
      # Defensive: the line must never start with a stray separator.
      line = helper.game_meta_line(year_only)
      expect(line).not_to start_with(" ")
      expect(line).not_to start_with("·")
      expect(line).not_to start_with("★")
    end

    it "drops empty year without leaving a trailing dot" do
      # Defensive: the line must never end with a stray separator.
      line = helper.game_meta_line(rating_only)
      expect(line).not_to end_with(" ")
      expect(line).not_to end_with("·")
    end

    it "uses the unicode star (U+2605)" do
      expect(helper.game_meta_line(both)).to include("★")
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
