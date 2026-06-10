# frozen_string_literal: true

module Pito
  module Game
    # Renders a full game detail card for use in chat messages.
    #
    # NAMESPACE GOTCHA: inside Pito::Game::*, the bareword `Game` resolves to
    # the Pito::Game MODULE. Use the fully-qualified ::Game constant to reference
    # the model — or simply receive the record as a param (preferred here).
    # Sibling components are referenced by their full name:
    #   Pito::ScoreBarComponent, Pito::TimeToBeatComponent.
    class DetailComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def cover_art_attached?
        @game.cover_art.attached?
      end

      def cover_art_url
        return nil unless cover_art_attached?

        @game.cover_art.variant(::Game::COVER_VARIANT)
      rescue StandardError
        nil
      end

      def developer_names
        names = Array(@game.developer_companies.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def publisher_names
        names = Array(@game.publisher_companies.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def release_label
        @game.release_label.presence
      end

      # Returns the de-duped operator tokens (ps/switch/steam) derived from
      # the IGDB platform names in game.platforms.  Returns [] when none match.
      def platform_tokens
        PlatformTokens.tokens(@game.platforms)
      end

      # Plain comma-joined platform display names (PlayStation / Switch / Steam),
      # rendered as a normal KV value — no chips.
      def platforms_label
        PlatformTokens.labels(@game.platforms)
      end

      # html_safe String of inline SVG logo <img> tags for each matched platform,
      # in PS → Switch → Steam order. Returns "".html_safe when none match.
      def platforms_icons
        PlatformTokens.icons_html(@game.platforms)
      end

      def summary
        @game.summary.presence
      end

      def genres_label
        names = Array(@game.genres.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def themes_label
        Array(@game.themes).reject(&:blank?).join(", ").presence
      end

      def perspectives_label
        Array(@game.player_perspectives).reject(&:blank?).join(", ").presence
      end

      def footage_hours
        @footage_hours ||= @game.footages.sum(:duration_seconds).to_i / 3600
      end
    end
  end
end
