# frozen_string_literal: true

require "rails_helper"

# ── Game::Traits::Derive — deterministic IGDB-fact -> derived-tag mapping
# (traits-design.md section 5) ──────────────────────────────────────────────
RSpec.describe Game::Traits::Derive, type: :service do
  def genre!(name)
    create(:genre, name: name)
  end

  describe "genre-mapped tags" do
    it "derives platformer from an exact case-insensitive Platform genre" do
      game = create(:game)
      game.genres << genre!("platform")

      described_class.call(game)
      expect(game.reload.trait_tags).to include("platformer")
      expect(game.trait_source("platformer")).to eq("derived")
    end

    it "derives simulation from genre Simulator" do
      game = create(:game)
      game.genres << genre!("Simulator")
      described_class.call(game)
      expect(game.reload.trait_tags).to include("simulation")
    end

    it "derives guns from genre Shooter" do
      game = create(:game)
      game.genres << genre!("Shooter")
      described_class.call(game)
      expect(game.reload.trait_tags).to include("guns")
    end

    it "does NOT match a genre substring (Platform-adventure must not match Platform)" do
      game = create(:game)
      game.genres << genre!("Platform-adventure")
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("platformer")
    end

    # Q32 wishlist (2026-07-20): adventure / role_playing / racing map to
    # synced IGDB genres; "racing" covers the owner's "driving" too.
    it "derives adventure, role_playing and racing from their IGDB genres" do
      game = create(:game)
      game.genres << genre!("Adventure")
      game.genres << genre!("Role-playing (RPG)")
      game.genres << genre!("Racing")

      described_class.call(game)
      expect(game.reload.trait_tags).to include("adventure", "role_playing", "racing")
      expect(game.trait_source("racing")).to eq("derived")
    end
  end

  describe "theme-mapped tags" do
    it "derives action/horror/survival/war from matching themes" do
      game = create(:game, themes: %w[Action Horror Survival Warfare])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("action", "horror", "survival", "war")
    end

    it "does not derive a theme tag when the theme is absent" do
      game = create(:game, themes: [ "Fantasy" ])
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("action", "horror", "survival", "war", "open_world")
    end

    # Q32 wishlist (2026-07-20): open-world maps to the synced IGDB theme.
    it "derives open_world from theme Open world" do
      game = create(:game, themes: [ "Open world" ])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("open_world")
      expect(game.trait_source("open_world")).to eq("derived")
    end
  end

  describe "time_consuming" do
    it "derives from ttb_main_seconds >= 40h" do
      game = create(:game, ttb_main_seconds: 144_000)
      described_class.call(game)
      expect(game.reload.trait_tags).to include("time_consuming")
    end

    it "derives from ttb_completionist_seconds >= 80h even when main is short" do
      game = create(:game, ttb_main_seconds: 3600, ttb_completionist_seconds: 288_000)
      described_class.call(game)
      expect(game.reload.trait_tags).to include("time_consuming")
    end

    it "does not derive when both are under threshold" do
      game = create(:game, ttb_main_seconds: 3600, ttb_completionist_seconds: 7200)
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("time_consuming")
    end

    it "is nil-safe when ttb columns are unset" do
      game = create(:game, ttb_main_seconds: nil, ttb_completionist_seconds: nil)
      expect { described_class.call(game) }.not_to raise_error
      expect(game.reload.trait_tags).not_to include("time_consuming")
    end
  end

  describe "acclaimed" do
    it "derives from a qualifying critics score" do
      game = create(:game, aggregated_rating: 90, aggregated_rating_count: 10)
      described_class.call(game)
      expect(game.reload.trait_tags).to include("acclaimed")
    end

    it "derives from a qualifying crowd-consensus fallback" do
      game = create(:game, total_rating: 90, total_rating_count: 150)
      described_class.call(game)
      expect(game.reload.trait_tags).to include("acclaimed")
    end

    it "does not derive when the score qualifies but the vote count doesn't" do
      game = create(:game, aggregated_rating: 90, aggregated_rating_count: 2)
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("acclaimed")
    end

    it "is nil-safe when rating columns are unset" do
      game = create(:game)
      expect { described_class.call(game) }.not_to raise_error
      expect(game.reload.trait_tags).not_to include("acclaimed")
    end
  end

  # ── L6 flip (2026-07-17): game_modes / hypes / age_ratings now sync ──────
  describe "game_modes-mapped tags" do
    it "derives multiplayer from game mode Multiplayer (case-insensitive exact)" do
      game = create(:game, game_modes: [ "multiplayer" ])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("multiplayer")
      expect(game.trait_source("multiplayer")).to eq("derived")
    end

    it "derives multiplayer from game mode Co-operative" do
      game = create(:game, game_modes: [ "Co-operative" ])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("multiplayer")
    end

    it "derives single_player from game mode Single player" do
      game = create(:game, game_modes: [ "Single player" ])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("single_player")
      expect(game.trait_source("single_player")).to eq("derived")
    end

    it "derives both when a game carries multiple modes (Elden Ring shape)" do
      game = create(:game, game_modes: [ "Single player", "Multiplayer", "Co-operative" ])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("multiplayer", "single_player")
    end

    it "does not derive either when game_modes is empty" do
      game = create(:game, game_modes: [])
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("multiplayer", "single_player")
    end
  end

  describe "hyped" do
    it "derives from hypes at the threshold" do
      game = create(:game, hypes: Game::Traits::Derive::HYPED_FOLLOWS_THRESHOLD)
      described_class.call(game)
      expect(game.reload.trait_tags).to include("hyped")
      expect(game.trait_source("hyped")).to eq("derived")
    end

    it "does not derive below the threshold" do
      game = create(:game, hypes: Game::Traits::Derive::HYPED_FOLLOWS_THRESHOLD - 1)
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("hyped")
    end

    it "is nil-safe when hypes is unset" do
      game = create(:game, hypes: nil)
      expect { described_class.call(game) }.not_to raise_error
      expect(game.reload.trait_tags).not_to include("hyped")
    end
  end

  describe "family_friendly" do
    it "derives from ESRB E" do
      game = create(:game, age_ratings: { "ESRB" => "E" })
      described_class.call(game)
      expect(game.reload.trait_tags).to include("family_friendly")
      expect(game.trait_source("family_friendly")).to eq("derived")
    end

    it "derives from ESRB E10+" do
      game = create(:game, age_ratings: { "ESRB" => "E10+" })
      described_class.call(game)
      expect(game.reload.trait_tags).to include("family_friendly")
    end

    it "derives from PEGI 3" do
      game = create(:game, age_ratings: { "PEGI" => "3" })
      described_class.call(game)
      expect(game.reload.trait_tags).to include("family_friendly")
    end

    it "derives from PEGI 7" do
      game = create(:game, age_ratings: { "PEGI" => "7" })
      described_class.call(game)
      expect(game.reload.trait_tags).to include("family_friendly")
    end

    it "does not derive from ESRB M (mature)" do
      game = create(:game, age_ratings: { "ESRB" => "M" })
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("family_friendly")
    end

    it "does not derive from PEGI 16" do
      game = create(:game, age_ratings: { "PEGI" => "16" })
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("family_friendly")
    end

    it "is nil-safe when age_ratings is empty" do
      game = create(:game, age_ratings: {})
      expect { described_class.call(game) }.not_to raise_error
      expect(game.reload.trait_tags).not_to include("family_friendly")
    end
  end

  describe "idempotency" do
    it "reports changed: false on a second run with unchanged facts" do
      game = create(:game, themes: [ "Action" ])
      first = described_class.call(game)
      expect(first[:changed]).to be true

      second = described_class.call(game.reload)
      expect(second).to eq(changed: false, skipped_owner: [])
    end
  end

  describe "self-healing a stale derived tag" do
    it "removes a previously-derived tag once its underlying fact no longer holds" do
      game = create(:game, themes: [ "Action" ])
      described_class.call(game)
      expect(game.reload.trait_tags).to include("action")

      game.update!(themes: [])
      described_class.call(game)
      expect(game.reload.trait_tags).not_to include("action")
    end

    it "never touches an owner-pinned derived tag, even after the fact stops holding" do
      game = create(:game, themes: [ "Action" ])
      Game::Traits::Apply.call(game: game, source: "owner", add_tags: [ "action" ])

      game.update!(themes: [])
      result = described_class.call(game.reload)

      expect(result[:skipped_owner]).to be_empty
      expect(game.reload.trait_tags).to include("action")
      expect(game.trait_source("action")).to eq("owner")
    end

    it "never re-adds an owner-pinned-absent derived tag even when the fact newly holds" do
      game = create(:game, themes: [])
      Game::Traits::Apply.call(game: game, source: "owner", remove_tags: [ "action" ])
      expect(game.reload.trait_source("action")).to eq("owner")

      game.update!(themes: [ "Action" ])
      result = described_class.call(game.reload)

      expect(result[:skipped_owner]).to include("action")
      expect(game.reload.trait_tags).not_to include("action")
      expect(game.trait_source("action")).to eq("owner")
    end
  end
end
