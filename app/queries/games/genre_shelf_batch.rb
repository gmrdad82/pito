# Phase 27 P27 reviewer follow-up (non-blocking concern #2,
# 2026-05-11) — single-pass batch query for the genre sub-shelves on
# `GET /games`.
#
# Before this query existed, `_genre_sub_shelf.html.erb` iterated each
# `Genre` in `@genres_for_shelf` and called both `base.count` and
# `base.order(...).limit(30).to_a` per genre. With N genres in the
# library that produced `2 * N` extra queries per request.
#
# The batch shape:
#
#   Games::GenreShelfBatch.new(genres: rel, cap: 30).data
#   #=> { genre_id => { count: Integer, games: Array<Game> } }
#
# Two queries total regardless of N:
#
#   1. Grouped count — `Game.where(primary_genre_id: ids).group(...)`.
#   2. Top-`cap`-per-genre fetch using a `ROW_NUMBER()` window
#      partitioned by `primary_genre_id`, ordered by `LOWER(title)`.
#
# The partial reads the map by genre id; missing entries (a stale id
# in the relation) yield `count: 0, games: []` so the partial keeps
# its current "render heading, no tiles" behaviour.
module Games
  class GenreShelfBatch
    DEFAULT_CAP = 30

    attr_reader :genres, :cap

    def initialize(genres:, cap: DEFAULT_CAP)
      @genres = genres
      @cap    = cap
    end

    # Materialise the batch. Memoised — repeated calls return the same
    # hash.
    def data
      @data ||= build_data
    end

    # Convenience: fetch one genre's slice with defensive fallback.
    def for(genre)
      data.fetch(genre.id, default_slice)
    end

    private

    def build_data
      ids = genres.map(&:id)
      return {} if ids.empty?

      counts = Game.where(primary_genre_id: ids).group(:primary_genre_id).count
      games_by_genre = fetch_top_games(ids)

      ids.index_with do |id|
        {
          count: counts.fetch(id, 0),
          games: games_by_genre.fetch(id, [])
        }
      end
    end

    # Single windowed query — `ROW_NUMBER()` partitioned by
    # `primary_genre_id`, ordered by `LOWER(games.title)`, capped at
    # `cap` rows per partition. Postgres-native; Rails connection runs
    # the raw SQL via `find_by_sql` so each row hydrates as a `Game`
    # ActiveRecord instance.
    def fetch_top_games(genre_ids)
      sql = <<~SQL.squish
        SELECT * FROM (
          SELECT games.*,
                 ROW_NUMBER() OVER (
                   PARTITION BY primary_genre_id
                   ORDER BY LOWER(games.title), games.id
                 ) AS rn
          FROM games
          WHERE primary_genre_id IN (#{genre_ids.map(&:to_i).join(',')})
        ) ranked
        WHERE rn <= #{cap.to_i}
      SQL

      Game.find_by_sql(sql).group_by(&:primary_genre_id)
    end

    def default_slice
      { count: 0, games: [] }
    end
  end
end
