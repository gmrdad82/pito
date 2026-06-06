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

        @game.cover_art.variant(resize_to_limit: [ 600, 800 ])
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

      def platforms_label
        platforms = Array(@game.platforms).reject(&:blank?)
        platforms.join(", ").presence
      end

      def owned_platforms_label
        tokens = @game.game_platform_ownerships.map(&:platform_token)
        return nil if tokens.blank?

        tokens.map { |token| I18n.t("pito.game.detail.platform_label.#{token}") }.join(", ")
      end

      def summary
        @game.summary.presence
      end

      def genres_label
        names = Array(@game.genres.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def footage_hours
        @footage_hours ||= @game.footages.sum(:duration_seconds).to_i / 3600
      end
    end
  end
end
