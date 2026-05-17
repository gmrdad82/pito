require "rails_helper"

# P27 reviewer follow-up (non-blocking concern #2, 2026-05-11) —
# single-pass batch resolver for the per-genre sub-shelves on
# `GET /games`. Asserts the contract:
#
#   - data is a Hash keyed by genre id
#   - each slice is `{ count: Integer, games: Array<Game> }`
#   - games are alphabetical case-insensitive, capped at `cap`
#   - missing genre ids fall back to `{ count: 0, games: [] }`
#   - the batch issues a flat 2 SELECTs regardless of N
RSpec.describe Games::GenreShelfBatch do
  let!(:adventure)  { Genre.create!(igdb_id: 9_201, name: "Adventure",  slug: "adventure") }
  let!(:rpg)        { Genre.create!(igdb_id: 9_202, name: "RPG",        slug: "rpg") }
  let!(:platformer) { Genre.create!(igdb_id: 9_203, name: "Platformer", slug: "platformer") }

  # Convenience — pin a game to a genre via the primary_genre_id
  # pointer (the same pointer the production sub-shelf reads).
  def pin(title, genre)
    g = create(:game, :synced, title: title, cover_image_id: "img-#{title.parameterize}")
    g.update_column(:primary_genre_id, genre.id)
    g
  end

  describe "happy: three genres with mixed game counts" do
    let!(:zelda)    { pin("Zelda BotW", adventure) }
    let!(:tunic)    { pin("Tunic",      adventure) }
    let!(:abzu)     { pin("ABZU",       adventure) }
    let!(:persona)  { pin("Persona 5",  rpg) }
    # platformer intentionally empty so it's filtered out upstream;
    # but we test that even if passed in, the batch handles 0.

    let(:genres) { Genre.where(id: [ adventure.id, rpg.id, platformer.id ]).order(:name) }
    let(:batch)  { described_class.new(genres: genres) }

    it "keys the data hash by genre id" do
      expect(batch.data.keys).to match_array([ adventure.id, rpg.id, platformer.id ])
    end

    it "returns the correct count per genre" do
      expect(batch.data[adventure.id][:count]).to eq(3)
      expect(batch.data[rpg.id][:count]).to eq(1)
      expect(batch.data[platformer.id][:count]).to eq(0)
    end

    it "orders the games alphabetical case-insensitive by title" do
      titles = batch.data[adventure.id][:games].map(&:title)
      expect(titles).to eq([ "ABZU", "Tunic", "Zelda BotW" ])
    end

    it "returns an empty Array for a genre with zero games" do
      expect(batch.data[platformer.id][:games]).to eq([])
    end

    it "#for(genre) returns the slice for that genre" do
      slice = batch.for(adventure)
      expect(slice[:count]).to eq(3)
      expect(slice[:games].map(&:title)).to eq([ "ABZU", "Tunic", "Zelda BotW" ])
    end

    it "#for(genre) on an unmapped id falls back to the empty slice" do
      unknown = Genre.create!(igdb_id: 9_999, name: "Unknown", slug: "unknown")
      expect(batch.for(unknown)).to eq(count: 0, games: [])
    end
  end

  describe "edge: cap honored at the partition level" do
    let!(:fixture_games) do
      # 35 games pinned to `adventure`; cap defaults to 30.
      35.times.map { |i| pin(format("%04d game", i + 1), adventure) }
    end

    it "limits games per genre to the cap (default 30)" do
      batch = described_class.new(genres: Genre.where(id: adventure.id))
      expect(batch.data[adventure.id][:games].length).to eq(30)
    end

    it "the count reflects the full total (not the cap)" do
      batch = described_class.new(genres: Genre.where(id: adventure.id))
      expect(batch.data[adventure.id][:count]).to eq(35)
    end

    it "honors a custom cap" do
      batch = described_class.new(genres: Genre.where(id: adventure.id), cap: 5)
      expect(batch.data[adventure.id][:games].length).to eq(5)
    end
  end

  describe "edge: empty input" do
    it "returns an empty hash when no genres are passed" do
      batch = described_class.new(genres: Genre.none)
      expect(batch.data).to eq({})
    end
  end

  # Phase 27 v2 spec 06 — optional `filter_scope:` narrows both the
  # grouped count AND the per-partition top-N to the filtered Game
  # subset. When the filter excludes every game in a genre, the
  # slice is `count: 0, games: []`.
  describe "filter_scope: argument" do
    let!(:zelda)   { pin("Zelda BotW", adventure) }
    let!(:tunic)   { pin("Tunic", adventure) }
    let!(:persona) { pin("Persona 5", rpg) }

    it "narrows the games to the filter_scope's subset" do
      filtered = Game.where(id: [ zelda.id, persona.id ])
      batch = described_class.new(
        genres: Genre.where(id: [ adventure.id, rpg.id ]),
        filter_scope: filtered
      )
      expect(batch.for(adventure)[:count]).to eq(1)
      expect(batch.for(adventure)[:games].map(&:title)).to eq([ "Zelda BotW" ])
      expect(batch.for(rpg)[:count]).to eq(1)
    end

    it "yields zero count / no games for a genre whose members are filtered out" do
      filtered = Game.where(id: persona.id)
      batch = described_class.new(
        genres: Genre.where(id: [ adventure.id, rpg.id ]),
        filter_scope: filtered
      )
      expect(batch.for(adventure)[:count]).to eq(0)
      expect(batch.for(adventure)[:games]).to eq([])
    end

    it "no filter_scope behaves identically to filter_scope: Game.all" do
      no_scope = described_class.new(
        genres: Genre.where(id: adventure.id)
      ).for(adventure)
      all_scope = described_class.new(
        genres: Genre.where(id: adventure.id),
        filter_scope: Game.all
      ).for(adventure)
      expect(all_scope[:count]).to eq(no_scope[:count])
      expect(all_scope[:games].map(&:id)).to eq(no_scope[:games].map(&:id))
    end
  end

  describe "flaw: single-pass query budget" do
    let!(:zelda)   { pin("Zelda BotW", adventure) }
    let!(:persona) { pin("Persona 5",  rpg) }

    it "issues exactly 2 SELECTs for N=2 genres (grouped count + windowed top-N)" do
      genres = Genre.where(id: [ adventure.id, rpg.id ]).to_a
      sql_count = 0
      callback = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name] == "SCHEMA"
        next if payload[:cached]
        sql_count += 1 if payload[:sql].to_s.match?(/\ASELECT/i)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.new(genres: genres).data
      end
      # 2 SELECTs: the grouped count + the windowed top-N (ROW_NUMBER).
      expect(sql_count).to eq(2)
    end

    it "the SELECT count stays at 2 when N grows to 5 genres" do
      3.times do |i|
        extra = Genre.create!(igdb_id: 9_400 + i, name: "Extra-#{i}", slug: "extra-#{i}")
        pin("Game-extra-#{i}", extra)
      end
      genres = Genre.order(:id).to_a
      sql_count = 0
      callback = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name] == "SCHEMA"
        next if payload[:cached]
        sql_count += 1 if payload[:sql].to_s.match?(/\ASELECT/i)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.new(genres: genres).data
      end
      expect(sql_count).to eq(2)
    end
  end
end
