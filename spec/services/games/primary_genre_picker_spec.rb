require "rails_helper"

# Phase 27 follow-up (2026-05-11) — primary-genre picker.
RSpec.describe Games::PrimaryGenrePicker do
  subject(:picker) { described_class.new }

  describe "#pick" do
    context "happy: explicit pin (rule 1)" do
      it "returns the pinned genre directly" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_001)
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_002)
        game      = create(:game, :synced, title: "Pinned Adventure")
        game.genres << rpg
        game.update_column(:primary_genre_id, adventure.id)

        # Rule 1 honors the pin even when it does NOT match any
        # linked genre on the join table (pinning is decoupled from
        # `game_genres`).
        expect(picker.pick(game)).to eq(adventure)
      end
    end

    context "happy: alphabetical fallback (rule 2)" do
      it "picks the first linked genre by canonical name ordering" do
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_011)
        adventure = create(:genre, name: "Adventure", igdb_id: 6_012)
        shooter   = create(:genre, name: "Shooter",   igdb_id: 6_013)
        game      = create(:game, title: "Multi-genre")
        game.genres << [ rpg, adventure, shooter ]
        # The GameGenre after_create_commit callback may have set a
        # primary already; clear it so rule 2 is the path under test.
        game.update_column(:primary_genre_id, nil)

        # "Adventure" < "RPG" < "Shooter" — alphabetical first wins.
        expect(picker.pick(game.reload)).to eq(adventure)
      end

      it "is deterministic across calls (same inputs → same pick)" do
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_021)
        adventure = create(:genre, name: "Adventure", igdb_id: 6_022)
        game      = create(:game, title: "Determinism check")
        game.genres << [ rpg, adventure ]
        game.update_column(:primary_genre_id, nil)

        first  = picker.pick(game.reload)
        second = picker.pick(game.reload)
        expect(first).to eq(second)
      end

      it "returns the single linked genre when only one is attached" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_031)
        game      = create(:game, title: "Solo genre")
        game.genres << adventure
        game.update_column(:primary_genre_id, nil)

        expect(picker.pick(game.reload)).to eq(adventure)
      end
    end

    context "edge: zero linked genres" do
      it "returns nil so the caller leaves primary_genre_id blank" do
        game = create(:game, title: "No genres attached")
        game.update_column(:primary_genre_id, nil)

        expect(picker.pick(game)).to be_nil
      end
    end

    context "edge: pinned genre gets deleted mid-flight" do
      it "falls through to the alphabetical pick after the FK on_delete: :nullify clears the pin" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_041)
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_042)
        pinned    = create(:genre, name: "Zombie pin", igdb_id: 6_043)
        game      = create(:game, title: "Stale pin")
        # Link two more genres (adventure + rpg) so the picker has
        # something to fall through to.
        GameGenre.create!(game: game, genre: adventure)
        GameGenre.create!(game: game, genre: rpg)
        # Manually pin to `pinned` without touching the join, then
        # delete that genre. The FK on_delete: :nullify clears the
        # pointer back to NULL.
        game.update_column(:primary_genre_id, pinned.id)
        pinned.destroy!

        # primary_genre_id is now NULL; rule 1 short-circuits; rule 2
        # picks the alphabetical-first remaining genre.
        expect(picker.pick(game.reload)).to eq(adventure)
      end
    end

    context "edge: nil game" do
      it "returns nil without raising" do
        expect(picker.pick(nil)).to be_nil
      end
    end
  end
end
