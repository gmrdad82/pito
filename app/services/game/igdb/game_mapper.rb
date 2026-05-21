# Phase 14 §1 — IGDB JSON → local-row attribute hashes.
#
# Stateless module. One method per resource type. The shape of every
# IGDB payload follows Note 4's "Fields we pull from IGDB" table.
#
# Conventions:
#   - `first_release_date` (Unix seconds) → `Time.at(...).utc.to_date`
#   - `cover.image_id` (string) → `cover_image_id`
#   - `external_games[category=1].uid` → `external_steam_app_id`
#   - `external_games[category=5].uid`  → DROPPED (GoG collapsed into Steam)
#   - `external_games[category=26].uid` → DROPPED (Epic collapsed into Steam)
#   - `involved_companies[developer=true]` → `game_developers` join
#   - `involved_companies[publisher=true]` → `game_publishers` join
#   - `game_time_to_beats.{hastily,normally,completely}` →
#     `ttb_{main,extras,completionist}_seconds`
#
# Phase 27 v2 spec 06 (2026-05-17 PC store collapse): GoG and Epic
# external rows are no longer mapped onto their own columns. The
# columns themselves are gone (`CollapsePcPlatformsIntoSteam`
# migration) and the PC-store ownership surface is unified under
# Steam. The mapper preserves `external_steam_app_id` and silently
# ignores categories 5 and 26.
#
# `map_game` returns ONLY IGDB-sourced columns. Local-only columns
# (`played_at`, `notes`, `hours_of_footage_manual`) are intentionally
# absent so a caller can `update!(map_game(...))` without clobbering
# local edits. Per-platform ownership (Phase 27 §1a) lives in
# `game_platform_ownerships` — the join survives sync untouched.
class Game
  module Igdb
    module GameMapper
      module_function

      def map_game(json, ttb_json = nil, external_json = nil)
        json ||= {}

        release_date = unix_to_date(json["first_release_date"])
        attrs = {
          igdb_id:                 json["id"],
          igdb_slug:               json["slug"],
          igdb_checksum:           json["checksum"],
          title:                   json["name"],
          summary:                 json["summary"],
          cover_image_id:          json.dig("cover", "image_id"),
          release_date:            release_date,
          release_year:            release_date&.year,
          igdb_rating:             round_rating(json["rating"]),
          igdb_rating_count:       json["rating_count"],
          aggregated_rating:       round_rating(json["aggregated_rating"]),
          aggregated_rating_count: json["aggregated_rating_count"],
          total_rating:            round_rating(json["total_rating"]),
          total_rating_count:      json["total_rating_count"]
        }

        # Phase 28 §01a — IGDB's `version_title` stamps the edition row.
        # `version_parent_id` is NOT mapped here: the IGDB payload's
        # `version_parent` field is an IGDB-side game id that needs
        # local resolution (create-or-update the parent first). See
        # `Game::Igdb::SyncGame#resolve_version_parent_id`.
        if json.key?("version_title") && json["version_title"].present?
          attrs[:version_title] = json["version_title"]
        end

        # 2026-05-19 — IGDB `alternative_names` is an array of
        # `{id, name, comment}` hashes. We persist only the `name`
        # strings (deduplicated, blanks dropped) into the local
        # `alternative_names` text[] column for omnisearch + Meili.
        # When IGDB omits the field entirely, the column resets to an
        # empty array so a previously-populated row whose alt names
        # were removed upstream stays in sync.
        if json.key?("alternative_names")
          attrs[:alternative_names] = extract_alternative_names(json["alternative_names"])
        end

        attrs.merge!(map_time_to_beat(ttb_json))
        attrs.merge!(map_external_games(external_json))
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

      def map_time_to_beat(ttb_json)
        json = ttb_json.is_a?(Array) ? ttb_json.first : ttb_json
        json ||= {}
        {
          ttb_main_seconds:          json["hastily"],
          ttb_extras_seconds:        json["normally"],
          ttb_completionist_seconds: json["completely"]
        }
      end

      # Phase 27 v2 spec 06 (2026-05-17 PC store collapse): the result
      # hash carries ONLY `external_steam_app_id`. GoG (category 5) and
      # Epic (category 26) external rows surface as IGDB platform
      # "ownability" signals (handled by `Game.on_platform("steam")`-
      # adjacent logic via the IGDB platforms join) but they no longer
      # populate dedicated columns — the columns themselves are gone.
      def map_external_games(external_json)
        list = Array(external_json)
        result = { external_steam_app_id: nil }
        list.each do |row|
          next unless row.is_a?(Hash)
          case row["category"]
          when Game::Igdb::Client::EXTERNAL_GAME_CATEGORY_STEAM
            result[:external_steam_app_id] ||= row["uid"]
          end
        end
        result
      end

      def map_genre(json)
        json ||= {}
        {
          igdb_id: json["id"],
          name:    json["name"],
          slug:    json["slug"]
        }
      end

      def map_platform(json)
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
        return nil if seconds.nil?
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
