# frozen_string_literal: true

module Pito
  module Game
    # Groups a game's per-platform releases BY DISPLAYED DATE for rendering (Item 24).
    #
    # Platforms that share the same displayed date collapse into ONE group (all
    # their logos on one line); platforms with different dates become separate
    # groups, ordered earliest-first. Tokens within a group follow
    # PlatformTokens::ORDER. This is where the "clobber when rendering" happens —
    # the DB keeps one distinct row per platform.
    #
    #   Pito::Game::PlatformReleaseGroups.call(game)
    #   # => [ { label: "July 31, 2026", tokens: ["ps", "steam"] },
    #   #      { label: "Q3 2026",        tokens: ["switch"] } ]
    module PlatformReleaseGroups
      module_function

      FAR_FUTURE = Date.new(9999, 12, 31)

      # @param game [Game]
      # @return [Array<Hash>] ordered groups: { label: String, tokens: Array<String> }
      def call(game)
        rows = game.platform_releases.to_a
        return [] if rows.empty?

        rows
          .group_by { |r| Pito::Formatter::ReleaseDate.call(r) }
          .map do |label, group|
            {
              label:    label,
              tokens:   group.map(&:platform_token).uniq.sort_by { |t| Pito::Game::PlatformTokens::ORDER.index(t) || 99 },
              sort_key: group.filter_map(&:release_date).min || FAR_FUTURE
            }
          end
          .sort_by { |g| g[:sort_key] }
          .map { |g| g.slice(:label, :tokens) }
      end
    end
  end
end
