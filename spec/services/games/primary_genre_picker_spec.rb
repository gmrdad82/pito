require "rails_helper"

# Phase 27 v2 spec 01 — primary-genre picker.
#
# Policy (2026-05-17 IGDB-order revision):
#
#   1. Explicit `primary_genre_id` pin wins.
#   2. Otherwise the picker orders the game's linked genres by
#      `game_genres.position ASC NULLS LAST, LOWER(genres.name) ASC,
#      genres.id ASC` and returns the first row.
#   3. Zero linked genres → nil.
#
# `game_genres.position` is written by `Igdb::SyncGame#sync_genres`
# from the IGDB payload's array index (0 = primary). Legacy rows
# (pre-2026-05-17) have NULL positions and fall through to the
# alphabetical secondary key.
RSpec.describe Games::PrimaryGenrePicker do
  subject(:picker) { described_class.new }

  describe "#pick" do
    context "happy: explicit pin (rule 1)" do
      it "returns the pinned genre directly" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_001)
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_002)
        # Plain (unsynced) game: the `:synced` trait would set
        # `igdb_synced_at` and trigger `after_save_commit` hooks
        # unrelated to the picker contract under test. The picker
        # itself does not care about sync state.
        game      = create(:game, title: "Pinned Adventure")
        game.genres << rpg
        game.update_column(:primary_genre_id, adventure.id)

        # Rule 1 honors the pin even when it does NOT match any
        # linked genre on the join table (pinning is decoupled from
        # `game_genres`).
        expect(picker.pick(game)).to eq(adventure)
      end
    end

    # Phase 27 v2 spec 01 follow-up (2026-05-17) — IGDB-order primary
    # picker. `game_genres.position` carries the IGDB payload's array
    # index; position 0 = IGDB primary; the picker honors that
    # ordering before falling back to alphabetical.
    context "happy: IGDB-order winner (rule 2 — position present)" do
      it "picks the row at position 0 (IGDB-first), not the alphabetical winner" do
        # Mandragora-style example: IGDB returns
        # [Role-playing, Adventure, Indie]. The alphabetical winner
        # would be "Adventure"; the IGDB-first winner is "Role-playing".
        rpg       = create(:genre, name: "Role-playing", igdb_id: 6_101)
        adventure = create(:genre, name: "Adventure",    igdb_id: 6_102)
        indie     = create(:genre, name: "Indie",        igdb_id: 6_103)
        game      = create(:game, title: "Mandragora")
        GameGenre.create!(game: game, genre: rpg,       position: 0)
        GameGenre.create!(game: game, genre: adventure, position: 1)
        GameGenre.create!(game: game, genre: indie,     position: 2)
        game.update_column(:primary_genre_id, nil)

        expect(picker.pick(game.reload)).to eq(rpg)
      end

      it "respects positions [3, 1, 2] for genres [A, B, C] — picks B (position 1)" do
        a = create(:genre, name: "A-genre", igdb_id: 6_111)
        b = create(:genre, name: "B-genre", igdb_id: 6_112)
        c = create(:genre, name: "C-genre", igdb_id: 6_113)
        game = create(:game, title: "Positions out of order")
        GameGenre.create!(game: game, genre: a, position: 3)
        GameGenre.create!(game: game, genre: b, position: 1)
        GameGenre.create!(game: game, genre: c, position: 2)
        game.update_column(:primary_genre_id, nil)

        # B at position 1 wins over A at position 3 even though A is
        # alphabetically first.
        expect(picker.pick(game.reload)).to eq(b)
      end

      it "returns the single linked genre when only one is attached (position present)" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_121)
        game      = create(:game, title: "Solo genre — positioned")
        GameGenre.create!(game: game, genre: adventure, position: 0)
        game.update_column(:primary_genre_id, nil)

        expect(picker.pick(game.reload)).to eq(adventure)
      end

      it "is deterministic across calls (same inputs → same pick)" do
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_131)
        adventure = create(:genre, name: "Adventure", igdb_id: 6_132)
        game      = create(:game, title: "Determinism check")
        GameGenre.create!(game: game, genre: rpg,       position: 0)
        GameGenre.create!(game: game, genre: adventure, position: 1)
        game.update_column(:primary_genre_id, nil)

        first  = picker.pick(game.reload)
        second = picker.pick(game.reload)
        expect(first).to eq(second)
        expect(first).to eq(rpg)
      end
    end

    # Defensive fallback — legacy rows that pre-date the position
    # column (2026-05-17 migration) have `game_genres.position IS NULL`
    # across every row. The `NULLS LAST` ordering keeps positioned rows
    # ahead of NULL rows; when EVERY row is NULL the secondary key
    # (alphabetical case-insensitive) drives the choice.
    context "fallback: legacy rows with no positions (rule 2 secondary key)" do
      it "picks the alphabetical winner when every position is NULL" do
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_201)
        adventure = create(:genre, name: "Adventure", igdb_id: 6_202)
        shooter   = create(:genre, name: "Shooter",   igdb_id: 6_203)
        game      = create(:game, title: "Legacy multi-genre")
        # Every row gets position NULL — the legacy state before the
        # 2026-05-17 follow-up migration.
        GameGenre.create!(game: game, genre: rpg,       position: nil)
        GameGenre.create!(game: game, genre: adventure, position: nil)
        GameGenre.create!(game: game, genre: shooter,   position: nil)
        game.update_column(:primary_genre_id, nil)

        # "Adventure" < "RPG" < "Shooter" alphabetically.
        expect(picker.pick(game.reload)).to eq(adventure)
      end

      it "prefers a positioned row over a NULL-position row, regardless of alphabetical order" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_211)
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_212)
        game      = create(:game, title: "Mixed positions")
        # Adventure would normally win alphabetically. Mark it NULL,
        # mark RPG position=0 — RPG should win (positioned beats NULL).
        GameGenre.create!(game: game, genre: adventure, position: nil)
        GameGenre.create!(game: game, genre: rpg,       position: 0)
        game.update_column(:primary_genre_id, nil)

        expect(picker.pick(game.reload)).to eq(rpg)
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
      it "falls through to the IGDB-order pick after the FK on_delete: :nullify clears the pin" do
        adventure = create(:genre, name: "Adventure", igdb_id: 6_241)
        rpg       = create(:genre, name: "RPG",       igdb_id: 6_242)
        pinned    = create(:genre, name: "Zombie pin", igdb_id: 6_243)
        game      = create(:game, title: "Stale pin")
        # Link two more genres so the picker has something to fall
        # through to. RPG at position 0 should win over Adventure at
        # position 1 — IGDB order beats alphabetical.
        GameGenre.create!(game: game, genre: rpg,       position: 0)
        GameGenre.create!(game: game, genre: adventure, position: 1)
        # Manually pin to `pinned` without touching the join, then
        # delete that genre. The FK on_delete: :nullify clears the
        # pointer back to NULL.
        game.update_column(:primary_genre_id, pinned.id)
        pinned.destroy!

        # primary_genre_id is now NULL; rule 1 short-circuits; rule 2
        # picks the position-0 row.
        expect(picker.pick(game.reload)).to eq(rpg)
      end
    end

    context "edge: nil game" do
      it "returns nil without raising" do
        expect(picker.pick(nil)).to be_nil
      end
    end

    # Phase 27 v2 spec 01 — case-insensitive alphabetical tie-break
    # at the SECONDARY key. Position is the PRIMARY key; alphabetical
    # `LOWER(name)` only fires when positions are equal (or both NULL).
    context "edge: case-insensitive alphabetical tie-break (NULL positions)" do
      it "treats Action / action / ACTION as equal lowercase keys and falls back to id" do
        upper  = create(:genre, name: "ACTION", igdb_id: 7_101)
        title  = create(:genre, name: "Action", igdb_id: 7_102)
        lower  = create(:genre, name: "action", igdb_id: 7_103)
        game   = create(:game, title: "Case mix")
        # All NULL positions so the alphabetical secondary fires.
        GameGenre.create!(game: game, genre: upper, position: nil)
        GameGenre.create!(game: game, genre: title, position: nil)
        GameGenre.create!(game: game, genre: lower, position: nil)
        game.update_column(:primary_genre_id, nil)

        # All three lowercase to "action"; the tertiary key (`id ASC`)
        # picks the lowest id → `upper` (created first).
        expect(picker.pick(game.reload)).to eq(upper)
      end

      it "puts lowercase 'adventure' before uppercase 'RPG' (Adventure < RPG)" do
        rpg       = create(:genre, name: "RPG",       igdb_id: 7_111)
        adventure = create(:genre, name: "adventure", igdb_id: 7_112)
        game      = create(:game, title: "Cross-case ordering")
        GameGenre.create!(game: game, genre: rpg,       position: nil)
        GameGenre.create!(game: game, genre: adventure, position: nil)
        game.update_column(:primary_genre_id, nil)

        # LOWER("adventure") = "adventure"; LOWER("RPG") = "rpg".
        # "adventure" < "rpg" so the lowercase row wins despite being
        # created later than the uppercase row.
        expect(picker.pick(game.reload)).to eq(adventure)
      end
    end

    # Phase 27 v2 spec 01 — unpersisted game flaw guard.
    context "edge: unpersisted game (no associations loaded)" do
      it "returns nil without raising (no in-memory genres association)" do
        unsaved = build(:game, title: "Unpersisted")
        expect(picker.pick(unsaved)).to be_nil
      end
    end
  end
end
