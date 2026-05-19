require "rails_helper"

# Wave F consolidation (2026-05-18) — Games::RatingHeatBarComponent.
#
# Synthesized rating heat-bar. Coverage:
#
#   - `TIERS` constant — 6 named tiers with inclusive lower bounds.
#   - `.synthesized_score(game)` — vote-weighted average across the
#     three IGDB rating triplets carried on `Game`.
#   - `.tier_for(score)` — tier slug for a numeric score with hard
#     boundaries at 25 / 50 / 60 / 70 / 80 / 90 (and `very_bad` below
#     25; `missing` for nil).
#   - `score:` override arg wins over game-derived computation.
#   - Render path emits the bar (with bubble + indicator) when a score
#     is present, and the muted variant when it is not.
#
# Rationale for stubs vs build_stubbed: the class methods are pure
# functions over the IGDB rating triplets. We construct lightweight
# stub objects for the score-math tests (no DB writes, no factory
# coupling) and use `build_stubbed(:game)` for the integration-style
# tests that also pass other game fields to the render path.
RSpec.describe Games::RatingHeatBarComponent, type: :component do
  # Build a lightweight stand-in for a `Game` carrying only the rating
  # triplet columns the synthesis formula reads. Avoids a DB hit and
  # keeps these unit tests fully isolated from the schema.
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
  # TIERS — constant shape + tier names + ordering.
  # ----------------------------------------------------------------

  describe "TIERS" do
    it "lists six named tiers" do
      expect(described_class::TIERS.length).to eq(6)
    end

    it "is frozen" do
      expect(described_class::TIERS).to be_frozen
    end

    it "names the six tiers `excellent`, `good`, `fair`, `meh`, `poor`, `bad`" do
      expect(described_class::TIERS.map(&:last))
        .to eq(%w[excellent good fair meh poor bad])
    end

    it "orders tiers high → low so iteration finds the first matching tier" do
      bounds = described_class::TIERS.map(&:first)
      expect(bounds).to eq([ 90, 80, 70, 60, 50, 25 ])
    end
  end

  # ----------------------------------------------------------------
  # .synthesized_score — vote-weighted average.
  # ----------------------------------------------------------------

  describe ".synthesized_score" do
    it "returns nil when the game is nil" do
      expect(described_class.synthesized_score(nil)).to be_nil
    end

    it "returns nil when no triplet has a positive vote count" do
      game = stub_game
      expect(described_class.synthesized_score(game)).to be_nil
    end

    it "returns nil when scores are present but all counts are zero" do
      game = stub_game(
        igdb:       [ 80, 0 ],
        aggregated: [ 90, 0 ],
        total:      [ 85, 0 ]
      )
      expect(described_class.synthesized_score(game)).to be_nil
    end

    it "returns nil when scores are present but all counts are nil" do
      game = stub_game(
        igdb:       [ 80, nil ],
        aggregated: [ 90, nil ],
        total:      [ 85, nil ]
      )
      expect(described_class.synthesized_score(game)).to be_nil
    end

    it "returns nil when counts are positive but scores are nil" do
      game = stub_game(
        igdb:       [ nil, 100 ],
        aggregated: [ nil, 50 ],
        total:      [ nil, 150 ]
      )
      expect(described_class.synthesized_score(game)).to be_nil
    end

    it "uses a single triplet when only one is populated" do
      game = stub_game(igdb: [ BigDecimal("80.0"), 10 ])
      expect(described_class.synthesized_score(game)).to eq(80)
    end

    it "vote-weights across two triplets — (80*10 + 90*30) / 40 = 87.5 → 88" do
      game = stub_game(
        igdb:       [ BigDecimal("80.0"), 10 ],
        aggregated: [ BigDecimal("90.0"), 30 ]
      )
      expect(described_class.synthesized_score(game)).to eq(88)
    end

    it "vote-weights across all three triplets and rounds to integer" do
      # (90.5*100 + 92.0*50 + 91.0*150) / (100+50+150) =
      # (9050 + 4600 + 13650) / 300 = 27300 / 300 = 91.0 → 91
      game = stub_game(
        igdb:       [ BigDecimal("90.50"), 100 ],
        aggregated: [ BigDecimal("92.00"), 50 ],
        total:      [ BigDecimal("91.00"), 150 ]
      )
      expect(described_class.synthesized_score(game)).to eq(91)
    end

    it "ignores triplets with zero votes when others are populated" do
      # Only the igdb triplet has a positive count; aggregated and total
      # are scored but uncounted → they MUST be dropped from the average.
      game = stub_game(
        igdb:       [ BigDecimal("80.0"), 10 ],
        aggregated: [ BigDecimal("100.0"), 0 ],
        total:      [ BigDecimal("100.0"), 0 ]
      )
      expect(described_class.synthesized_score(game)).to eq(80)
    end

    it "ignores negative or nil counts mixed with valid contributions" do
      # Only the aggregated triplet is valid; igdb has nil count, total
      # has zero count.
      game = stub_game(
        igdb:       [ BigDecimal("70.0"), nil ],
        aggregated: [ BigDecimal("90.0"), 20 ],
        total:      [ BigDecimal("100.0"), 0 ]
      )
      expect(described_class.synthesized_score(game)).to eq(90)
    end
  end

  # ----------------------------------------------------------------
  # .tier_for — boundary resolution.
  # ----------------------------------------------------------------

  describe ".tier_for" do
    it "returns `missing` for nil" do
      expect(described_class.tier_for(nil)).to eq("missing")
    end

    {
      100 => "excellent",
       90 => "excellent",   # inclusive lower bound
       89 => "good",
       80 => "good",        # inclusive lower bound
       79 => "fair",
       70 => "fair",        # inclusive lower bound
       69 => "meh",
       60 => "meh",         # inclusive lower bound
       59 => "poor",
       50 => "poor",        # inclusive lower bound
       49 => "bad",
       25 => "bad",         # inclusive lower bound
       24 => "very_bad",
        0 => "very_bad"     # fall-through below 25
    }.each do |score, expected_tier|
      it "maps #{score} to `#{expected_tier}`" do
        expect(described_class.tier_for(score)).to eq(expected_tier)
      end
    end
  end

  # ----------------------------------------------------------------
  # #score — override vs derived behavior.
  # ----------------------------------------------------------------

  describe "#score" do
    it "returns the `score:` override when given (game is ignored)" do
      game = stub_game(igdb: [ BigDecimal("50.0"), 100 ])
      component = described_class.new(game: game, score: 88)
      expect(component.score).to eq(88)
    end

    it "computes from the game when no override is passed" do
      game = stub_game(igdb: [ BigDecimal("80.0"), 10 ])
      component = described_class.new(game: game)
      expect(component.score).to eq(80)
    end

    it "returns nil when no game and no override is passed" do
      component = described_class.new
      expect(component.score).to be_nil
    end
  end

  # ----------------------------------------------------------------
  # Instance-form helpers — kept for backwards compatibility.
  # ----------------------------------------------------------------

  describe "#synthesized_score (instance form)" do
    it "delegates to the class method" do
      game = stub_game(igdb: [ BigDecimal("80.0"), 10 ])
      component = described_class.new(game: game)
      expect(component.synthesized_score).to eq(80)
    end
  end

  describe "#tier_for (instance form)" do
    it "delegates to the class method" do
      component = described_class.new
      expect(component.tier_for(72)).to eq("fair")
    end
  end

  describe "#tier" do
    it "resolves the tier for the override score when given" do
      component = described_class.new(score: 95)
      expect(component.tier).to eq("excellent")
    end

    it "resolves the tier for the game-derived score" do
      game = stub_game(igdb: [ BigDecimal("55.0"), 10 ])
      component = described_class.new(game: game)
      expect(component.tier).to eq("poor")
    end

    it "resolves to `missing` when no score is available" do
      component = described_class.new
      expect(component.tier).to eq("missing")
    end
  end

  # ----------------------------------------------------------------
  # Render path — happy + muted-fallback.
  # ----------------------------------------------------------------

  describe "#render" do
    it "renders the bar with bubble + indicator when score is present" do
      render_inline(described_class.new(score: 90))
      expect(page).to have_css("div.rating-heat-bar[data-score='90'][data-tier='excellent']")
      expect(page).to have_css("span.rating-heat-bar-bubble", text: "90")
      expect(page).to have_css("div.rating-heat-bar-indicator")
    end

    it "stamps the --score CSS custom property with the integer score" do
      render_inline(described_class.new(score: 72))
      bar = page.find("div.rating-heat-bar")
      expect(bar[:style]).to include("--score: 72")
      expect(bar[:style]).to include("--tier-color: var(--color-rating-fair)")
    end

    it "renders the muted variant when score is nil" do
      render_inline(described_class.new)
      expect(page).to have_css("div.rating-heat-bar.rating-heat-bar--muted[data-tier='missing']")
      expect(page).not_to have_css("span.rating-heat-bar-bubble")
      expect(page).not_to have_css("div.rating-heat-bar-indicator")
    end

    it "renders score=0 as a real bar (not the muted fallback)" do
      # 0 is a legitimate value (very_bad tier); it must NOT collapse to
      # the missing-rating muted variant.
      render_inline(described_class.new(score: 0))
      expect(page).to have_css("div.rating-heat-bar[data-score='0'][data-tier='very_bad']")
      expect(page).to have_css("span.rating-heat-bar-bubble", text: "0")
      expect(page).not_to have_css("div.rating-heat-bar--muted")
    end

    it "renders score=25 at the bad boundary" do
      render_inline(described_class.new(score: 25))
      expect(page).to have_css("div.rating-heat-bar[data-tier='bad']")
    end

    it "renders score=50 at the poor boundary" do
      render_inline(described_class.new(score: 50))
      expect(page).to have_css("div.rating-heat-bar[data-tier='poor']")
    end

    it "renders score=90 at the excellent boundary" do
      render_inline(described_class.new(score: 90))
      expect(page).to have_css("div.rating-heat-bar[data-tier='excellent']")
    end

    it "renders score=100 in the excellent tier" do
      render_inline(described_class.new(score: 100))
      expect(page).to have_css("div.rating-heat-bar[data-tier='excellent']")
    end

    it "renders from a build_stubbed game with no rating data as muted" do
      game = build_stubbed(:game)
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.rating-heat-bar--muted")
    end

    it "renders from a build_stubbed :synced game as a real bar" do
      game = build_stubbed(:game, :synced)
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.rating-heat-bar:not(.rating-heat-bar--muted)")
      expect(page).to have_css("span.rating-heat-bar-bubble")
    end
  end

  # ----------------------------------------------------------------
  # Wave C reveal — animated stub-then-reveal while `game.resyncing?`
  # is true.
  #
  # While resyncing the indicator tick + bubble park at the bar's
  # left edge (`--score: 0`) and the bubble copy renders as an em-dash
  # (`—`). The bar itself stays the FULL gradient bar (NOT the muted
  # variant) even when the score would otherwise be nil, so that the
  # CSS `transition: left 600ms ease-in-out` on the indicator + bubble
  # can animate them rightward to the real position once the Turbo
  # morph carries the post-sync score into the DOM.
  # ----------------------------------------------------------------

  describe "Wave C reveal — animated stub-then-reveal" do
    let(:resyncing_game) do
      build_stubbed(:game, :synced, resyncing: true)
    end

    let(:settled_synced_game) do
      build_stubbed(:game, :synced, resyncing: false)
    end

    let(:bare_settled_game) do
      build_stubbed(:game, resyncing: false)
    end

    context "when game.resyncing? is true" do
      before do
        render_inline(described_class.new(game: resyncing_game))
      end

      it "renders tick at left: 0% (stubbed)" do
        # The indicator and bubble both consume the `--score` custom
        # property via `calc(var(--score) * 1%)`; stubbing the variable
        # to 0 is what parks both at the bar's left edge.
        bar = page.find("div.rating-heat-bar")
        expect(bar[:style]).to include("--score: 0")
        # Indicator still rendered (NOT the muted variant) so it can
        # animate from left:0 to its real position post-morph.
        expect(page).to have_css("div.rating-heat-bar-indicator")
      end

      it "score bubble shows em-dash (—)" do
        bubble = page.find("span.rating-heat-bar-bubble")
        expect(bubble.text.strip).to eq("—")
      end

      it "renders full bar (not the muted variant) even when score would be nil" do
        # The bare `:synced` factory has rating data, so synthesize a
        # game with no rating triplets AND resyncing: true to prove
        # the resync branch wins over the nil-score muted fallback.
        nilly = build_stubbed(:game, resyncing: true)
        render_inline(described_class.new(game: nilly))

        expect(page).to have_css("div.rating-heat-bar")
        expect(page).not_to have_css("div.rating-heat-bar--muted")
        expect(page).to have_css("span.rating-heat-bar-bubble", text: "—")
        expect(page).to have_css("div.rating-heat-bar-indicator")
      end

      it "data-resyncing='yes' attribute present" do
        expect(page).to have_css("div.rating-heat-bar[data-resyncing='yes']")
      end
    end

    context "when game.resyncing? is false" do
      it "renders tick at computed real position" do
        render_inline(described_class.new(game: settled_synced_game))
        bar = page.find("div.rating-heat-bar")
        # `:synced` factory yields a synthesized score of 91 (see the
        # vote-weighted average tests above using the same triplets).
        expect(bar[:style]).to include("--score: 91")
        expect(page).to have_css("div.rating-heat-bar-indicator")
        expect(page).not_to have_css("div.rating-heat-bar[data-resyncing='yes']")
      end

      it "score bubble shows numeric score" do
        render_inline(described_class.new(game: settled_synced_game))
        bubble = page.find("span.rating-heat-bar-bubble")
        expect(bubble.text.strip).to eq("91")
      end

      it "falls back to muted variant when score is nil" do
        # A bare (non-:synced) game has no rating triplets, so the
        # synthesized score is nil. With resyncing: false, the muted
        # variant is what renders.
        render_inline(described_class.new(game: bare_settled_game))
        expect(page).to have_css("div.rating-heat-bar.rating-heat-bar--muted[data-tier='missing']")
        expect(page).not_to have_css("span.rating-heat-bar-bubble")
        expect(page).not_to have_css("div.rating-heat-bar-indicator")
      end
    end
  end
end
