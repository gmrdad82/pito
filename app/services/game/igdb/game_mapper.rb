# IGDB JSON → local-row attribute hashes.
#
# Stateless module. One method per resource type. The shape of every
# IGDB payload follows Note 4's "Fields we pull from IGDB" table.
#
# Conventions:
#   - `first_release_date` (Unix seconds) → `Time.at(...).utc.to_date`
#   - `cover.image_id` (string) → `cover_image_id`
#   - `external_games` → DROPPED (columns removed in schema reset; `external_steam_app_id` no longer stored)
#   - `involved_companies[developer=true]` → `game_developers` join
#   - `involved_companies[publisher=true]` → `game_publishers` join
#   - `game_time_to_beats.{hastily,normally,completely}` →
#     `ttb_{main,extras,completionist}_seconds`
#
# `map_game` returns ONLY IGDB-sourced columns. Local-only columns
# are intentionally absent so a caller can `update!(map_game(...))`
# without clobbering local edits.
class Game
  module Igdb
    module GameMapper
      module_function

      def map_game(json, ttb_json = nil)
        json ||= {}

        attrs = {
          igdb_id:                 json["id"],
          igdb_slug:               json["slug"],
          title:                   json["name"],
          summary:                 json["summary"],
          cover_image_id:          json.dig("cover", "image_id"),
          igdb_rating:             round_rating(json["rating"]),
          igdb_rating_count:       json["rating_count"],
          aggregated_rating:       round_rating(json["aggregated_rating"]),
          aggregated_rating_count: json["aggregated_rating_count"],
          total_rating:            round_rating(json["total_rating"]),
          total_rating_count:      json["total_rating_count"]
        }

        attrs.merge!(map_release_date(json))

        # 2026-05-19 — IGDB `alternative_names` is an array of
        # `{id, name, comment}` hashes. We persist only the `name`
        # strings (deduplicated, blanks dropped) into the local
        # `alternative_names` text[] column for omnisearch.
        # When IGDB omits the field entirely, the column resets to an
        # empty array so a previously-populated row whose alt names
        # were removed upstream stays in sync.
        if json.key?("alternative_names")
          attrs[:alternative_names] = extract_alternative_names(json["alternative_names"])
        end

        # IGDB `platforms` is an array of {id, name, slug}; we persist the
        # display names into the local `platforms` text[] column (shown as
        # "platforms available" in the game detail message).
        if json.key?("platforms")
          attrs[:platforms] = extract_platform_names(json["platforms"])
        end

        # IGDB `themes` (Action, Science fiction, Horror…) and
        # `player_perspectives` (Third person, Side view…) — name strings into
        # the local text[] columns; they drive the recommendation engine's
        # theme + perspective signals.
        attrs[:themes] = extract_platform_names(json["themes"]) if json.key?("themes")
        if json.key?("player_perspectives")
          attrs[:player_perspectives] = extract_platform_names(json["player_perspectives"])
        end

        # IGDB `game_modes` (Single player, Multiplayer, Co-operative…) —
        # same name-string extraction as `themes` above (no game mode is
        # named "Arcade", so the shared helper's platform-specific strip
        # is a no-op here). Feeds Game::Traits::Derive's multiplayer /
        # single_player mapping (traits-design.md L6).
        attrs[:game_modes] = extract_platform_names(json["game_modes"]) if json.key?("game_modes")

        # IGDB `hypes` — pre-release follow count, raw integer passthrough.
        # Feeds Game::Traits::Derive's `hyped` mapping.
        attrs[:hypes] = json["hypes"] if json.key?("hypes")

        # IGDB `age_ratings` — see extract_age_ratings for the shape.
        # Feeds Game::Traits::Derive's `family_friendly` mapping.
        attrs[:age_ratings] = extract_age_ratings(json["age_ratings"]) if json.key?("age_ratings")

        attrs.merge!(map_time_to_beat(ttb_json))
        attrs
      end

      # Pulls non-blank, deduplicated `name` strings out of the IGDB
      # `alternative_names` payload (which is an array of
      # `{id, name, comment}` hashes). Returns `[]` when the payload
      # is nil / not an array / empty — never nil, so the `null: false`
      # constraint on the column always holds.
      def extract_alternative_names(payload)
        Array(payload)
          .select { |row| row.is_a?(Hash) }
          .map { |row| row["name"].to_s.strip }
          .reject(&:empty?)
          .uniq
      end

      # Pulls non-blank, deduplicated platform `name` strings out of the IGDB
      # `platforms` payload. Returns `[]` (never nil) so the `null: false`
      # column constraint always holds. "Arcade" is stripped — the owner dropped
      # the platform in v1.4.0 and doesn't want it stored at all (2026-07-10);
      # existing rows were scrubbed by StripArcadeFromGamePlatforms.
      def extract_platform_names(payload)
        Array(payload)
          .select { |row| row.is_a?(Hash) }
          .map { |row| row["name"].to_s.strip }
          .reject(&:empty?)
          .reject { |name| name.casecmp?("Arcade") }
          .uniq
      end

      # Pulls {organization name => rating text} out of the IGDB
      # `age_ratings` payload — one row per rating board (ESRB, PEGI,
      # USK…), each nesting `organization.name` and
      # `rating_category.rating` (the post-2025 IGDB v4 schema; verified
      # LIVE 2026-07-17 — see Game::Igdb::Client::GAME_FIELDS). Keyed by
      # org name (not an array) so Game::Traits::Derive can look up
      # `age_ratings["ESRB"]` directly. Returns {} (never nil) so the
      # `null: false` column constraint always holds; a row missing either
      # nested value is skipped — nothing useful to key it by.
      def extract_age_ratings(payload)
        Array(payload)
          .select { |row| row.is_a?(Hash) }
          .each_with_object({}) do |row, acc|
            org = row.dig("organization", "name").to_s.strip
            rating = row.dig("rating_category", "rating").to_s.strip
            acc[org] = rating if org.present? && rating.present?
          end
      end

      def map_time_to_beat(ttb_json)
        json = ttb_json.is_a?(Array) ? ttb_json.first : ttb_json
        json ||= {}
        {
          ttb_main_seconds:          json["hastily"],
          ttb_extras_seconds:        json["normally"],
          ttb_completionist_seconds: json["completely"]
        }
      end

      # IGDB release_dates[] → pito 5-column component hash.
      #
      # 1. Picks the canonical row — the one whose `date` equals
      #    `first_release_date`, falling back to the most-precise
      #    non-TBD row when `first_release_date` is null.
      # 2. Translates IGDB `category` (0..7) into the component shape.
      # 3. Delegates to `Pito::Games::ReleaseDateMapper` for the
      #    canonical 5-column output.
      def map_release_date(json)
        first_release_date = unix_to_date(json["first_release_date"])
        rows = Array(json["release_dates"])

        components = if rows.any?
                       canonical_row(first_release_date, rows)
        elsif first_release_date
                       # No release_dates association — fall back to
                       # treating first_release_date as day precision.
                       {
                         year:  first_release_date.year,
                         month: first_release_date.month,
                         day:   first_release_date.day
                       }
        else
                       {}
        end

        Pito::Games::ReleaseDateMapper.call(components)
      end

      # Precision rank: lower = more precise.
      # 0 day | 1 month | 3..6 quarters | 2 year | 7 TBD
      RELEASE_DATE_PRECISION = {
        0 => 0, 1 => 1,
        3 => 2, 4 => 2, 5 => 2, 6 => 2,
        2 => 3,
        7 => 4
      }.freeze

      def canonical_row(first_release_date, rows)
        row = if first_release_date
                # Pick the row whose date matches first_release_date.
                target_unix = Time.utc(first_release_date.year, first_release_date.month, first_release_date.day).to_i
                rows.find { |r| r["date"] == target_unix }
        else
                # first_release_date is null — pick the most-precise
                # non-TBD row (lowest precision rank, excluding 7).
                non_tbd = rows.reject { |r| r["category"] == 7 }
                non_tbd.min_by { |r| RELEASE_DATE_PRECISION[r["category"].to_i] }
        end

        return {} unless row

        translate_igdb_category(row)
      end

      def translate_igdb_category(row)
        category = row["category"].to_i
        year     = row["y"]

        case category
        when 0 # day
          # IGDB release_dates rows have NO `d` field — the DAY lives only in the
          # `date` unix timestamp (y/m are given). Reading a nonexistent `row["d"]`
          # left release_day NULL for every game (every title stuck in
          # `awaiting_release`, release_date pinned to the 1st). Derive it from `date`.
          { year: year, month: row["m"], day: unix_to_date(row["date"])&.day }
        when 1 # month
          { year: year, month: row["m"] }
        when 2 # year
          { year: year }
        when 3, 4, 5, 6 # Q1..Q4
          { year: year, quarter: category - 2 }
        when 7 # TBD
          {}
        else
          {}
        end
      end

      def map_genre(json)
        json ||= {}
        {
          igdb_id: json["id"],
          name:    json["name"],
          slug:    json["slug"]
        }
      end

      def map_company(json)
        json ||= {}
        {
          igdb_id: json["id"],
          name:    json["name"],
          slug:    json["slug"]
        }
      end

      def developers(involved_companies)
        Array(involved_companies)
          .select { |row| row.is_a?(Hash) && row["developer"] && row["company"].is_a?(Hash) }
          .map { |row| map_company(row["company"]) }
          .uniq { |row| row[:igdb_id] }
      end

      def publishers(involved_companies)
        Array(involved_companies)
          .select { |row| row.is_a?(Hash) && row["publisher"] && row["company"].is_a?(Hash) }
          .map { |row| map_company(row["company"]) }
          .uniq { |row| row[:igdb_id] }
      end

      def unix_to_date(seconds)
        # Epoch 0 is IGDB's missing-date sentinel, not 1970-01-01 — treating it
        # as real would fabricate day-1 precision on a day-precision row.
        return nil if seconds.nil? || seconds.to_i.zero?
        Time.at(seconds.to_i).utc.to_date
      rescue StandardError
        nil
      end

      def round_rating(value)
        return nil if value.nil?
        value.to_d.round(2)
      end
    end
  end
end
