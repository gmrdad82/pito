# frozen_string_literal: true

module Pito
  module Game
    # Renders a game's release date(s) PER PLATFORM (Item 24) as the value cell of
    # the show-game "Release" kv-row.
    #
    # - Platforms sharing a date collapse to one line: <logos> <date> (all logos).
    # - Differing dates render one line each, earliest first, with that date's logos.
    # - A game with no per-platform rows yet (never re-synced, or no recognised
    #   platforms) falls back to the single derived release label, no logos.
    class PlatformReleaseComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def call
        return tag.span(fallback_label, class: "text-fg") if groups.empty?

        safe_join(groups.map { |group|
          tag.div(class: "pito-platform-release__row") do
            safe_join([
              Pito::Game::PlatformTokens.icons_html_for_tokens(group[:tokens]),
              tag.span(group[:label], class: "text-fg")
            ])
          end
        })
      end

      private

      def groups
        @groups ||= Pito::Game::PlatformReleaseGroups.call(@game)
      end

      def fallback_label
        Pito::Formatter::ReleaseDate.call(@game)
      end
    end
  end
end
