# frozen_string_literal: true

module Pito
  module Video
    # Renders a SLIM linked-game card for use under a video detail in chat.
    #
    # A small 180px cover on the LEFT and a key/value table on the RIGHT with
    # rows: title, genres, perspective, theme, publisher, developer, release
    # date, total footage. Unlike Pito::Game::DetailComponent it carries NO
    # time-to-beat / score bars — total footage is a plain KV value formatted
    # via Pito::Formatter::FootageHours.
    #
    # NAMESPACE GOTCHA: inside Pito::Video::*, the bareword `Video` resolves to
    # the Pito::Video MODULE. Use the fully-qualified ::Game constant to
    # reference the game model — or simply receive the record as a param
    # (preferred here).
    class LinkedGameCardComponent < ViewComponent::Base
      def initialize(game:)
        @game = game
      end

      def cover_attached?
        @game.cover_art.attached?
      end

      # Small cover variant (180×240) — the slim card's left column. Mirrors the
      # game detail card's cover helper/markup (Pito::ImagePath, image_tag).
      def cover_url
        Pito::ImagePath.call(@game.cover_art, variant: ::Game::COVER_VARIANT)
      end

      def title
        @game.title
      end

      def genres_label
        names = Array(@game.genres.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def perspectives_label
        Array(@game.player_perspectives).reject(&:blank?).join(", ").presence
      end

      def themes_label
        Array(@game.themes).reject(&:blank?).join(", ").presence
      end

      def publisher_names
        names = Array(@game.publisher_companies.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def developer_names
        names = Array(@game.developer_companies.map(&:name)).reject(&:blank?)
        names.join(", ").presence
      end

      def release_label
        @game.release_label.presence
      end

      # Total footage as a decimal-hours value — "5h" / "12.5h", or "—" when none.
      def footage_label
        Pito::Formatter::FootageHours.call(@game.footage_hours)
      end
    end
  end
end
