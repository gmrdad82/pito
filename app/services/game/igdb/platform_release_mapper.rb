# frozen_string_literal: true

class Game
  module Igdb
    # IGDB `release_dates[]` → per-platform-GROUP release component hashes (Item 24).
    #
    # Groups the rows by platform TOKEN (ps / switch / xbox / steam, via
    # Pito::Game::PlatformTokens) and, for each token, keeps the MOST PRECISE row
    # (day > month > quarter > year). Unrecognised platforms (e.g. Stadia) and TBD
    # rows are dropped. The IGDB category → component translation is reused from
    # GameMapper so the two mappers never diverge.
    #
    #   Game::Igdb::PlatformReleaseMapper.call(json)
    #   # => { "ps" => {year:2026, month:7, day:31}, "xbox" => {year:2026, quarter:3}, ... }
    module PlatformReleaseMapper
      module_function

      # @param json [Hash, nil] the IGDB game payload (needs release_dates[].platform.name)
      # @return [Hash{String=>Hash}] token → component hash (year/quarter/month/day)
      def call(json)
        rows = Array((json || {})["release_dates"])
        by_token = {}

        rows.each do |row|
          name = row.dig("platform", "name")
          next if name.blank?

          token = Pito::Game::PlatformTokens.tokens([ name ]).first
          next unless token

          components = GameMapper.translate_igdb_category(row)
          next if components.blank?

          current = by_token[token]
          by_token[token] = components if current.nil? || precision(components) < precision(current)
        end

        by_token
      end

      # Precision rank — lower is more precise (day 0 < month 1 < quarter 2 < year 3).
      def precision(components)
        return 0 if components[:day]
        return 1 if components[:month]
        return 2 if components[:quarter]

        3
      end
    end
  end
end
