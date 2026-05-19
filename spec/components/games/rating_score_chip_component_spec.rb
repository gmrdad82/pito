require "rails_helper"

# Wave F consolidation (2026-05-18) — Games::RatingScoreChipComponent.
#
# Small inline chip for the bundle-modal "all games" table. Reuses the
# heat-bar's class-level helpers
# (`Games::RatingHeatBarComponent.synthesized_score` /
# `Games::RatingHeatBarComponent.tier_for`) so the synthesized score and
# the tier resolution stay canonical to one place. The chip's only
# rendering signal is its `background-color`, sourced from `TIER_BG_COLOR`.
#
# Coverage:
#   - `TIER_BG_COLOR` — seven-tier palette (covers the 6 named tiers
#     plus the `very_bad` fall-through).
#   - `#score` delegates to `RatingHeatBarComponent.synthesized_score`.
#   - `#tier`  delegates to `RatingHeatBarComponent.tier_for(score)`.
#   - `#background_color` returns the tier's hex from the palette, with
#     a `very_bad` fallback for unknown tiers.
#   - Render: blank when score is nil; tier-colored chip when score is
#     present.
RSpec.describe Games::RatingScoreChipComponent, type: :component do
  def stub_game(igdb: [ nil, nil ], aggregated: [ nil, nil ], total: [ nil, nil ])
    instance_double(
      "Game",
      igdb_rating:             igdb[0],
      igdb_rating_count:       igdb[1],
      aggregated_rating:       aggregated[0],
      aggregated_rating_count: aggregated[1],
      total_rating:            total[0],
      total_rating_count:      total[1]
    )
  end

  # ----------------------------------------------------------------
  # TIER_BG_COLOR — seven-tier palette.
  # ----------------------------------------------------------------

  describe "TIER_BG_COLOR" do
    it "covers every tier the heat-bar can resolve to" do
      expect(described_class::TIER_BG_COLOR.keys)
        .to contain_exactly("very_bad", "bad", "poor", "meh", "fair", "good", "excellent")
    end

    it "is frozen" do
      expect(described_class::TIER_BG_COLOR).to be_frozen
    end

    {
      "very_bad"  => "#7a2020",
      "bad"       => "#c08454",
      "poor"      => "#c08454",
      "meh"       => "#ffb86c",
      "fair"      => "#f1fa8c",
      "good"      => "#a8e063",
      "excellent" => "#50fa7b"
    }.each do |tier, hex|
      it "maps tier `#{tier}` to #{hex}" do
        expect(described_class::TIER_BG_COLOR[tier]).to eq(hex)
      end
    end
  end

  # ----------------------------------------------------------------
  # #score — delegates to RatingHeatBarComponent.synthesized_score.
  # ----------------------------------------------------------------

  describe "#score" do
    it "delegates to `Games::RatingHeatBarComponent.synthesized_score`" do
      game = stub_game(igdb: [ BigDecimal("80.0"), 10 ])
      expect(Games::RatingHeatBarComponent)
        .to receive(:synthesized_score).with(game).and_call_original
      expect(described_class.new(game: game).score).to eq(80)
    end

    it "returns nil when the game has no IGDB rating data" do
      game = stub_game
      expect(described_class.new(game: game).score).to be_nil
    end

    it "returns the vote-weighted score for a game with rating triplets" do
      # (90.5*100 + 92.0*50 + 91.0*150) / 300 = 27300 / 300 = 91.0 → 91
      game = stub_game(
        igdb:       [ BigDecimal("90.50"), 100 ],
        aggregated: [ BigDecimal("92.00"), 50 ],
        total:      [ BigDecimal("91.00"), 150 ]
      )
      expect(described_class.new(game: game).score).to eq(91)
    end
  end

  # ----------------------------------------------------------------
  # #tier — delegates to RatingHeatBarComponent.tier_for(score).
  # ----------------------------------------------------------------

  describe "#tier" do
    it "delegates to `Games::RatingHeatBarComponent.tier_for`" do
      game = stub_game(igdb: [ BigDecimal("95.0"), 10 ])
      expect(Games::RatingHeatBarComponent)
        .to receive(:tier_for).with(95).and_call_original
      expect(described_class.new(game: game).tier).to eq("excellent")
    end

    it "returns `missing` when the score is nil" do
      game = stub_game
      expect(described_class.new(game: game).tier).to eq("missing")
    end

    {
      95 => "excellent",
      85 => "good",
      72 => "fair",
      62 => "meh",
      55 => "poor",
      30 => "bad",
      10 => "very_bad"
    }.each do |score, expected_tier|
      it "resolves score=#{score} to tier `#{expected_tier}`" do
        game = stub_game(igdb: [ BigDecimal(score.to_s), 10 ])
        expect(described_class.new(game: game).tier).to eq(expected_tier)
      end
    end
  end

  # ----------------------------------------------------------------
  # #background_color — palette lookup with very_bad fallback.
  # ----------------------------------------------------------------

  describe "#background_color" do
    it "returns the palette hex for the resolved tier" do
      game = stub_game(igdb: [ BigDecimal("95.0"), 10 ])
      expect(described_class.new(game: game).background_color).to eq("#50fa7b")
    end

    it "returns the `very_bad` hex when the score is nil (missing → fallback)" do
      # `tier` resolves to `missing` for nil scores; `missing` is not in
      # TIER_BG_COLOR, so the fallback (`very_bad` hex) wins.
      game = stub_game
      expect(described_class.new(game: game).background_color).to eq("#7a2020")
    end

    it "returns the bad-tier hex for a score just below the poor boundary" do
      game = stub_game(igdb: [ BigDecimal("30.0"), 10 ])
      expect(described_class.new(game: game).background_color).to eq("#c08454")
    end

    it "returns the very_bad-tier hex for a score below 25" do
      game = stub_game(igdb: [ BigDecimal("10.0"), 10 ])
      expect(described_class.new(game: game).background_color).to eq("#7a2020")
    end
  end

  # ----------------------------------------------------------------
  # Render path — blank when no score, chip when present.
  # ----------------------------------------------------------------

  describe "#render" do
    it "renders nothing when the game has no rating triplets" do
      game = stub_game
      result = render_inline(described_class.new(game: game))
      expect(result.to_s.strip).to be_blank
    end

    it "renders a `span.rating-score-chip` with the score text when present" do
      game = stub_game(igdb: [ BigDecimal("95.0"), 10 ])
      render_inline(described_class.new(game: game))
      expect(page).to have_css("span.rating-score-chip", text: "95")
    end

    it "stamps `data-tier` with the resolved tier slug" do
      game = stub_game(igdb: [ BigDecimal("72.0"), 10 ])
      render_inline(described_class.new(game: game))
      expect(page).to have_css("span.rating-score-chip[data-tier='fair']")
    end

    it "stamps the tier's background color as inline style" do
      game = stub_game(igdb: [ BigDecimal("95.0"), 10 ])
      render_inline(described_class.new(game: game))
      chip = page.find("span.rating-score-chip")
      expect(chip[:style]).to include("background-color: #50fa7b")
    end

    {
      95 => "#50fa7b",
      85 => "#a8e063",
      72 => "#f1fa8c",
      62 => "#ffb86c",
      55 => "#c08454",
      30 => "#c08454",
      10 => "#7a2020"
    }.each do |score, hex|
      it "renders score=#{score} with background-color #{hex}" do
        game = stub_game(igdb: [ BigDecimal(score.to_s), 10 ])
        render_inline(described_class.new(game: game))
        chip = page.find("span.rating-score-chip")
        expect(chip[:style]).to include("background-color: #{hex}")
      end
    end

    it "renders nothing for a build_stubbed game with no rating data" do
      game = build_stubbed(:game)
      result = render_inline(described_class.new(game: game))
      expect(result.to_s.strip).to be_blank
    end

    it "renders the chip for a build_stubbed :synced game (which carries rating triplets)" do
      game = build_stubbed(:game, :synced)
      render_inline(described_class.new(game: game))
      expect(page).to have_css("span.rating-score-chip")
    end
  end
end
