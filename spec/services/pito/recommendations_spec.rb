# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendations, type: :service do
  # 1024-dim unit vector with a single hot dimension → predictable cosine.
  # Two vectors at the same hot index have distance ≈ 0 (score ≈ 100).
  # Two vectors at different hot indices are orthogonal: distance = 1 (score 0).
  def vec(index, value: 1.0)
    Array.new(1024, 0.0).tap { |a| a[index] = value }
  end

  # ---------- .call (import step-5 dummy) -----------------------------------

  describe ".call" do
    it "returns true regardless of arguments" do
      expect(described_class.call).to be true
      expect(described_class.call(nil)).to be true
      expect(described_class.call(:anything, "extra")).to be true
    end
  end

  # ---------- .similar_games ------------------------------------------------

  describe ".similar_games" do
    let(:game) { create(:game, title: "Source Game") }

    before { game.update_column(:summary_embedding, vec(0)) }

    context "when game is nil" do
      it "returns []" do
        expect(described_class.similar_games(nil)).to eq([])
      end
    end

    context "when game has no embedding" do
      before { game.update_column(:summary_embedding, nil) }

      it "returns []" do
        expect(described_class.similar_games(game)).to eq([])
      end
    end

    context "with no filters" do
      it "returns blended Result structs (game + score + breakdown) best-first" do
        near = create(:game, title: "Near Game")
        near.update_column(:summary_embedding, vec(0))
        # An orthogonal game with no shared facets scores 0 and is floored out.
        create(:game, title: "Far Game").update_column(:summary_embedding, vec(1))

        results = described_class.similar_games(game, limit: 10)
        expect(results).to all(be_a(Pito::Recommendation::GameSimilarity::Result))
        expect(results.map(&:game)).to eq([ near ])
        expect(results.first.score).to eq(45) # embedding-only blend (E .45 × 100)
        expect(results.first.breakdown[:e]).to eq(100.0)
      end

      it "honours the limit" do
        3.times { |i| create(:game).update_column(:summary_embedding, vec(0, value: 0.5 + i * 0.1)) }
        expect(described_class.similar_games(game, limit: 2).size).to eq(2)
      end

      it "excludes the source game from results" do
        create(:game, title: "Other").update_column(:summary_embedding, vec(0))
        games = described_class.similar_games(game).map(&:game)
        expect(games).not_to include(game)
      end
    end

    context "filter: genre" do
      let(:genre_rpg) { create(:genre, slug: "rpg",     name: "RPG") }
      let(:genre_fps) { create(:genre, slug: "fps",     name: "FPS") }

      it "keeps only games sharing the genre slug" do
        rpg_game = create(:game, title: "RPG Match")
        rpg_game.update_column(:summary_embedding, vec(0))
        create(:game_genre, game: rpg_game, genre: genre_rpg)

        fps_game = create(:game, title: "FPS No-Match")
        fps_game.update_column(:summary_embedding, vec(0, value: 0.99))
        create(:game_genre, game: fps_game, genre: genre_fps)

        results = described_class.similar_games(game, filters: { genre: "rpg" })
        expect(results.map(&:game)).to include(rpg_game)
        expect(results.map(&:game)).not_to include(fps_game)
      end

      it "accepts an array of genre slugs" do
        rpg_game = create(:game, title: "RPG")
        rpg_game.update_column(:summary_embedding, vec(0))
        create(:game_genre, game: rpg_game, genre: genre_rpg)

        fps_game = create(:game, title: "FPS")
        fps_game.update_column(:summary_embedding, vec(0, value: 0.98))
        create(:game_genre, game: fps_game, genre: genre_fps)

        results = described_class.similar_games(game, filters: { genre: %w[rpg fps] })
        returned_titles = results.map { |r| r.game.title }
        expect(returned_titles).to include("RPG", "FPS")
      end
    end

    context "filter: year" do
      it "keeps only games released in the given year" do
        old = create(:game, title: "Old Game", release_year: 2020)
        old.update_column(:summary_embedding, vec(0))
        new_game = create(:game, title: "New Game", release_year: 2024)
        new_game.update_column(:summary_embedding, vec(0, value: 0.99))

        results = described_class.similar_games(game, filters: { year: 2024 })
        expect(results.map(&:game)).to include(new_game)
        expect(results.map(&:game)).not_to include(old)
      end
    end

    context "filter: developer" do
      it "keeps only games from the given developer (case-insensitive)" do
        dev = create(:company, name: "FromSoftware")
        soulslike = create(:game, title: "Elden Ring")
        soulslike.update_column(:summary_embedding, vec(0))
        create(:game_developer, game: soulslike, company: dev)

        other = create(:game, title: "Unrelated")
        other.update_column(:summary_embedding, vec(0, value: 0.99))

        results = described_class.similar_games(game, filters: { developer: "fromsoftware" })
        expect(results.map(&:game)).to include(soulslike)
        expect(results.map(&:game)).not_to include(other)
      end
    end

    context "filter: publisher" do
      it "keeps only games from the given publisher (case-insensitive)" do
        pub = create(:company, name: "Bandai Namco")
        published = create(:game, title: "Published")
        published.update_column(:summary_embedding, vec(0))
        create(:game_publisher, game: published, company: pub)

        unpublished = create(:game, title: "Indie")
        unpublished.update_column(:summary_embedding, vec(0, value: 0.99))

        results = described_class.similar_games(game, filters: { publisher: "bandai namco" })
        expect(results.map(&:game)).to include(published)
        expect(results.map(&:game)).not_to include(unpublished)
      end
    end

    context "filter: platform" do
      it "keeps only games on the given platform" do
        pc = create(:game, title: "PC Game")
        pc.update_column(:summary_embedding, vec(0))
        pc.update_column(:platforms, [ "PC" ])

        console = create(:game, title: "Console Only")
        console.update_column(:summary_embedding, vec(0, value: 0.99))
        console.update_column(:platforms, [ "PlayStation 5" ])

        results = described_class.similar_games(game, filters: { platform: "pc" })
        expect(results.map(&:game)).to include(pc)
        expect(results.map(&:game)).not_to include(console)
      end
    end

    context "filter: score (minimum)" do
      it "keeps only games meeting the minimum score" do
        high = create(:game, title: "High Score")
        high.update_column(:summary_embedding, vec(0))
        high.update_column(:score, 85)

        low = create(:game, title: "Low Score")
        low.update_column(:summary_embedding, vec(0, value: 0.99))
        low.update_column(:score, 40)

        results = described_class.similar_games(game, filters: { score: 75 })
        expect(results.map(&:game)).to include(high)
        expect(results.map(&:game)).not_to include(low)
      end

      it "drops games with no score" do
        scoreless = create(:game, title: "No Score")
        scoreless.update_column(:summary_embedding, vec(0))
        scoreless.update_column(:score, nil)

        results = described_class.similar_games(game, filters: { score: 1 })
        expect(results.map(&:game)).not_to include(scoreless)
      end
    end

    context "filter: ttb (time-to-beat buckets)" do
      it "keeps short games (<5h)" do
        short = create(:game, title: "Quick Game")
        short.update_column(:summary_embedding, vec(0))
        short.update_column(:ttb_main_seconds, 2 * 3600) # 2h

        long_game = create(:game, title: "Epic RPG")
        long_game.update_column(:summary_embedding, vec(0, value: 0.99))
        long_game.update_column(:ttb_main_seconds, 80 * 3600) # 80h

        results = described_class.similar_games(game, filters: { ttb: "short" })
        expect(results.map(&:game)).to include(short)
        expect(results.map(&:game)).not_to include(long_game)
      end

      it "keeps medium games (5–20h)" do
        medium = create(:game, title: "Medium Game")
        medium.update_column(:summary_embedding, vec(0))
        medium.update_column(:ttb_main_seconds, 10 * 3600) # 10h

        results = described_class.similar_games(game, filters: { ttb: "medium" })
        expect(results.map(&:game)).to include(medium)
      end

      it "keeps long games (>20h)" do
        long_game = create(:game, title: "Long RPG")
        long_game.update_column(:summary_embedding, vec(0))
        long_game.update_column(:ttb_main_seconds, 50 * 3600) # 50h

        results = described_class.similar_games(game, filters: { ttb: "long" })
        expect(results.map(&:game)).to include(long_game)
      end

      it ":complexity is an alias for :ttb" do
        short = create(:game, title: "Short")
        short.update_column(:summary_embedding, vec(0))
        short.update_column(:ttb_main_seconds, 3 * 3600)

        results = described_class.similar_games(game, filters: { complexity: "short" })
        expect(results.map(&:game)).to include(short)
      end

      it "passes through games when the ttb filter value is unrecognised" do
        any = create(:game, title: "Any Game")
        any.update_column(:summary_embedding, vec(0))
        any.update_column(:ttb_main_seconds, 10 * 3600)

        results = described_class.similar_games(game, filters: { ttb: "unknown_bucket" })
        expect(results.map(&:game)).to include(any)
      end

      it "drops games with no ttb data when ttb filter is set" do
        no_ttb = create(:game, title: "No TTB")
        no_ttb.update_column(:summary_embedding, vec(0))
        no_ttb.update_column(:ttb_main_seconds, nil)

        results = described_class.similar_games(game, filters: { ttb: "short" })
        expect(results.map(&:game)).not_to include(no_ttb)
      end
    end

    context "combined filters (genre + year)" do
      let(:genre_rpg) { create(:genre, slug: "rpg", name: "RPG") }

      it "intersects both filters (only games passing ALL conditions are returned)" do
        # Passes both: RPG + 2024
        both_pass = create(:game, title: "Both pass", release_year: 2024)
        both_pass.update_column(:summary_embedding, vec(0))
        create(:game_genre, game: both_pass, genre: genre_rpg)

        # Only genre passes, wrong year
        wrong_year = create(:game, title: "Wrong year", release_year: 2020)
        wrong_year.update_column(:summary_embedding, vec(0, value: 0.99))
        create(:game_genre, game: wrong_year, genre: genre_rpg)

        # Only year passes, wrong genre
        wrong_genre = create(:game, title: "Wrong genre", release_year: 2024)
        wrong_genre.update_column(:summary_embedding, vec(0, value: 0.98))

        results = described_class.similar_games(game, filters: { genre: "rpg", year: 2024 })
        returned = results.map(&:game)
        expect(returned).to include(both_pass)
        expect(returned).not_to include(wrong_year)
        expect(returned).not_to include(wrong_genre)
      end
    end

    context "when all candidates are filtered out" do
      it "returns []" do
        fps_game = create(:game, title: "FPS")
        fps_game.update_column(:summary_embedding, vec(0))

        results = described_class.similar_games(game, filters: { year: 9999 })
        expect(results).to eq([])
      end
    end

    context "Result struct" do
      it "carries game, score (0–100 Integer), and a signal breakdown" do
        near = create(:game, title: "Near")
        near.update_column(:summary_embedding, vec(0))

        result = described_class.similar_games(game).first
        expect(result.game).to eq(near)
        expect(result.score).to be_a(Integer)
        expect(result.score).to be_between(0, 100)
        expect(result.breakdown).to include(:e, :g, :d, :p, :s)
      end
    end
  end

  # ---------- .channels_for -------------------------------------------------

  describe ".channels_for" do
    let(:game) { create(:game, title: "Lies of P") }

    before { game.update_column(:summary_embedding, vec(0)) }

    it "returns [] for nil game" do
      expect(described_class.channels_for(nil)).to eq([])
    end

    it "returns [] when game has no embedding" do
      game.update_column(:summary_embedding, nil)
      expect(described_class.channels_for(game)).to eq([])
    end

    it "delegates to Game::ChannelRecommendation and returns its Results" do
      channel = create(:channel, title: "Soulslike Central")
      vid = create(:video, channel: channel)
      vid.update_column(:summary_embedding, vec(0))

      results = described_class.channels_for(game)
      expect(results).to all(be_a(Game::ChannelRecommendation::Result))
      expect(results.map(&:channel)).to include(channel)
      expect(results.first.score).to be_between(0, 100)
    end

    it "respects the limit keyword" do
      3.times do
        ch = create(:channel)
        vid = create(:video, channel: ch)
        vid.update_column(:summary_embedding, vec(0))
      end
      expect(described_class.channels_for(game, limit: 1).size).to eq(1)
    end
  end

  # ---------- .games_for ----------------------------------------------------

  describe ".games_for" do
    let(:channel) { create(:channel, title: "Soulslike Central") }

    def probe_video(embedding, views: 100)
      create(:video, channel: channel).tap do |v|
        v.update_column(:summary_embedding, embedding)
        Pito::Stats.set(v, :views, views)
      end
    end

    it "returns [] for nil channel" do
      expect(described_class.games_for(nil)).to eq([])
    end

    it "returns [] when channel has no embedded videos" do
      create(:video, channel: channel) # no embedding
      expect(described_class.games_for(channel)).to eq([])
    end

    it "delegates to Channel::GameRecommendation and returns its Results" do
      probe_video(vec(0))
      g = create(:game, title: "Elden Ring")
      g.update_column(:summary_embedding, vec(0))

      results = described_class.games_for(channel)
      expect(results).to all(be_a(Channel::GameRecommendation::Result))
      expect(results.map(&:game)).to include(g)
      expect(results.first.score).to be_between(0, 100)
    end

    it "respects the limit keyword" do
      probe_video(vec(0))
      3.times { |i| create(:game).update_column(:summary_embedding, vec(0, value: 0.5 + i * 0.1)) }
      expect(described_class.games_for(channel, limit: 1).size).to eq(1)
    end
  end
end
