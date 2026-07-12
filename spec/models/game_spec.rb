# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game, type: :model do
  describe "score auto-recomputation" do
    it "recomputes score when a rating field changes" do
      game = create(:game,
                    igdb_rating: 80.0, igdb_rating_count: 100)
      expect(game.score).to eq(80)

      game.update!(igdb_rating: 90.0)
      expect(game.score).to eq(90)
    end

    it "raises ScoreDriftError when rating changes would drift score beyond threshold" do
      game = create(:game,
                    igdb_rating: 80.0, igdb_rating_count: 100)
      expect(game.score).to eq(80)

      expect { game.update!(igdb_rating: 0.0, igdb_rating_count: 100) }
        .to raise_error(Pito::Error::ScoreDrift)
    end

    it "allows drift within threshold" do
      game = create(:game,
                    igdb_rating: 80.0, igdb_rating_count: 100)
      expect(game.score).to eq(80)

      # 80 → 55 = 25-point drift, within the 30-point threshold
      game.update!(igdb_rating: 55.0, igdb_rating_count: 100)
      expect(game.score).to eq(55)
    end

    it "allows a first real score to jump from 0 (a new game, not a glitched swing)" do
      game = create(:game, igdb_rating: 82.0, igdb_rating_count: 100)
      game.update_column(:score, 0) # a never-really-scored game sitting at 0

      # An IGDB sync writes real ratings → auto-recompute from 0 must NOT raise,
      # even though the jump (0 → ~82) is far beyond the 30-point drift guard.
      expect { game.update!(igdb_rating: 82.0, igdb_rating_count: 200) }
        .not_to raise_error
      expect(game.reload.score).to be > described_class::SCORE_DRIFT_THRESHOLD
    end

    it "does not recompute score when non-rating fields change" do
      game = create(:game,
                    title: "Original",
                    igdb_rating: 75.0, igdb_rating_count: 50)
      expect(game.score).to eq(75)

      expect { game.update!(title: "Renamed") }
        .not_to(change { game.reload.score })
    end
  end

  describe "#recompute_score!" do
    it "recomputes and persists the score, bypassing the drift guard" do
      game = create(:game,
                    igdb_rating: 90.0, igdb_rating_count: 200)
      game.update_column(:score, 0)

      expect { game.recompute_score! }
        .to change { game.reload.score }.from(0).to(90)
    end
  end

  # Contract for the release-date representation. See
  # `docs/architecture.md` § "Game release-date representation".
  describe "release-date components" do
    describe "validations" do
      it "is valid with day precision (year + month + day)" do
        game = build(:game, release_year: 2026, release_month: 10, release_day: 15)
        expect(game).to be_valid
      end

      it "is valid with month precision (year + month, no day)" do
        game = build(:game, release_year: 2026, release_month: 10)
        expect(game).to be_valid
      end

      it "is valid with quarter precision (year + quarter, no month)" do
        game = build(:game, release_year: 2026, release_quarter: 3)
        expect(game).to be_valid
      end

      it "is valid with year-only precision" do
        game = build(:game, release_year: 2026)
        expect(game).to be_valid
      end

      it "is valid with all components nil (TBA)" do
        game = build(:game, release_year: nil, release_quarter: nil,
                            release_month: nil, release_day: nil)
        expect(game).to be_valid
      end

      it "is valid with month + day and no year (manual 'Christmas' entry)" do
        game = build(:game, release_year: nil, release_month: 12, release_day: 25)
        expect(game).to be_valid
      end

      it "rejects quarter and month set together" do
        game = build(:game, release_year: 2026, release_quarter: 3, release_month: 7)
        expect(game).not_to be_valid
        expect(game.errors[:release_quarter]).to be_present
      end

      it "rejects day without month" do
        game = build(:game, release_year: 2026, release_day: 15)
        expect(game).not_to be_valid
        expect(game.errors[:release_day]).to be_present
      end

      it "rejects quarter outside 1..4" do
        game = build(:game, release_year: 2026, release_quarter: 5)
        expect(game).not_to be_valid
        expect(game.errors[:release_quarter]).to be_present
      end

      it "rejects month outside 1..12" do
        game = build(:game, release_year: 2026, release_month: 13)
        expect(game).not_to be_valid
        expect(game.errors[:release_month]).to be_present
      end

      it "rejects an impossible calendar date (Feb 31)" do
        game = build(:game, release_year: 2026, release_month: 2, release_day: 31)
        expect(game).not_to be_valid
      end
    end

    describe "before_save :recompute_release_date" do
      it "writes day-precision release_date" do
        game = create(:game, release_year: 2026, release_month: 10, release_day: 15)
        expect(game.release_date).to eq(Date.new(2026, 10, 15))
      end

      it "writes the first of the month for month precision" do
        game = create(:game, release_year: 2026, release_month: 10)
        expect(game.release_date).to eq(Date.new(2026, 10, 1))
      end

      it "writes the first day of the quarter for quarter precision" do
        game = create(:game, release_year: 2026, release_quarter: 3)
        expect(game.release_date).to eq(Date.new(2026, 7, 1))
      end

      it "writes January 1 for year-only precision" do
        game = create(:game, release_year: 2026)
        expect(game.release_date).to eq(Date.new(2026, 1, 1))
      end

      it "writes nil for TBA" do
        game = create(:game, release_year: nil)
        expect(game.release_date).to be_nil
      end

      it "writes nil for month-day-only entries (no year)" do
        game = create(:game, release_year: nil, release_month: 12, release_day: 25)
        expect(game.release_date).to be_nil
      end
    end

    describe "scopes and predicates" do
      it ".released_in(year) filters by release_year" do
        create(:game, release_year: 2025)
        create(:game, release_year: 2026)
        expect(Game.released_in(2025).count).to eq(1)
      end

      it ".tba returns games with release_year nil" do
        create(:game, release_year: 2026)
        create(:game, release_year: nil)
        expect(Game.tba.count).to eq(1)
      end

      it ".upcoming returns future-dated and TBA games" do
        create(:game, release_year: 2024, release_month: 1, release_day: 1)            # past
        create(:game, release_year: Date.current.year + 5)                              # future
        create(:game, release_year: nil)                                                # TBA
        expect(Game.upcoming.count).to eq(2)
      end

      it "#released? is true for past dates" do
        game = build(:game, release_year: 2024, release_month: 1, release_day: 1)
        expect(game).to be_released
      end

      it "#released? is false for future dates" do
        game = build(:game, release_year: Date.current.year + 5)
        expect(game).not_to be_released
      end

      it "#released? is false for TBA" do
        game = build(:game, release_year: nil)
        expect(game).not_to be_released
      end

      it "#tba? is true when synced and year unknown" do
        game = build(:game, release_year: nil, igdb_synced_at: Time.current)
        expect(game).to be_tba
      end

      it "#tba? is false when not yet synced (distinct from 'sync says TBA')" do
        game = build(:game, release_year: nil, igdb_synced_at: nil)
        expect(game).not_to be_tba
      end
    end

    describe "Christmas-any-year query (the (release_month, release_day) index)" do
      it "finds games released on Dec 25 across years" do
        create(:game, release_year: 2024, release_month: 12, release_day: 25)
        create(:game, release_year: 2026, release_month: 12, release_day: 25)
        create(:game, release_year: 2026, release_month: 12, release_day: 24)
        expect(Game.where(release_month: 12, release_day: 25).count).to eq(2)
      end
    end
  end

  # ── cover_art named variants ─────────────────────────────────────────────────

  describe "cover_art named variants" do
    let(:reflection) { Game.attachment_reflections["cover_art"] }

    it "declares a :detail named variant (resize_to_limit 450×600)" do
      expect(reflection.named_variants).to have_key(:detail)
    end

    it "declares a :strip named variant (resize_to_fill 180×240)" do
      expect(reflection.named_variants).to have_key(:strip)
    end

    context "with a cover attached" do
      let(:game) { create(:game) }

      before do
        game.cover_art.attach(
          io:           StringIO.new("fake-cover-bytes"),
          filename:     "cover-#{game.id}.jpg",
          content_type: "image/jpeg"
        )
      end

      it "resolves a host-less proxy path for the :detail variant" do
        url = Pito::ImagePath.call(game.cover_art, variant: :detail)
        expect(url).to be_present
        expect(url).to start_with("/")
      end

      it "resolves a host-less proxy path for the :strip variant" do
        url = Pito::ImagePath.call(game.cover_art, variant: :strip)
        expect(url).to be_present
        expect(url).to start_with("/")
      end
    end
  end

  # ── audience counters (G26.2) ─────────────────────────────────────────────────
  #
  # A game carries no stats of its own — #view_count / #like_count are the SUM
  # of its LINKED vids' Pito::Stats rows (link-graph-first), 0 when unlinked.

  describe "#view_count / #like_count" do
    let(:game)    { create(:game) }
    let(:channel) { create(:channel) }

    def link_video_with_stats(views: nil, likes: nil)
      video = create(:video, channel: channel)
      create(:video_game_link, game: game, video: video)
      Pito::Stats.set(video, :views, views) if views
      Pito::Stats.set(video, :likes, likes) if likes
      video
    end

    # G28: the readers consume the game's own MATERIALIZED Pito::Stats rows
    # (written by Game::StatsRefresh at link edits + stats passes) — they
    # never live-sum linked vids at render time.
    it "reads the materialized views row" do
      Pito::Stats.set(game, :views, 1_250)
      expect(game.view_count).to eq(1_250)
    end

    it "reads the materialized likes row" do
      Pito::Stats.set(game, :likes, 42)
      expect(game.like_count).to eq(42)
    end

    it "returns 0 before the first rollup and when no vids are linked" do
      expect(game.view_count).to eq(0)
      expect(game.like_count).to eq(0)
    end

    it "does not live-sum: linked vids' stats don't show until StatsRefresh runs" do
      link_video_with_stats(views: 1_000, likes: 40)
      expect(game.view_count).to eq(0)

      Game::StatsRefresh.call(game)
      expect(game.view_count).to eq(1_000)
      expect(game.like_count).to eq(40)
    end
  end

  describe ".picker_page" do
    it "pages by PICKER_PAGE_SIZE, case-stable, zero overlap, exact continuity" do
      stub_const("Game::PICKER_PAGE_SIZE", 3)
      %w[apple Banana cherry Delta echo].each { |t| create(:game, title: t) }

      p1, c1 = Game.picker_page
      expect(p1.size).to eq(3)
      expect(c1).to be_present

      p2, c2 = Game.picker_page(after: c1)
      expect(p2.size).to eq(2)
      expect(c2).to be_nil

      expect((p1 + p2).map(&:title).map(&:downcase))
        .to eq(%w[apple banana cherry delta echo])
      expect((p1.map(&:id) & p2.map(&:id))).to be_empty
    end

    it "treats a malformed cursor as the first page" do
      create(:game, title: "Solo")
      rows, = Game.picker_page(after: "garbage!!")
      expect(rows).not_to be_empty
    end
  end
end
