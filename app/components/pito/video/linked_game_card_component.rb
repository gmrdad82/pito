# frozen_string_literal: true

module Pito
  module Video
    # Renders a linked-game card for use under a video detail in chat.
    #
    # Mirrors Pito::Game::DetailComponent's detail layout: a BIG game cover on
    # the LEFT — bounded to the 374×210 16:9 box with the slow Ken-Burns vertical
    # pan (shared Z29 CSS) — and a key/value table on the RIGHT with rows: title,
    # id, genres, perspective, theme, publisher, developer, release date, total
    # footage, price. Two columns on desktop (md:flex-row, 374px left), stacking
    # to single-column on mobile (<768px). Unlike Pito::Game::DetailComponent it
    # carries NO time-to-beat / score bars — total footage is a plain KV value
    # formatted via Pito::Formatter::FootageHours.
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

      # Big detail cover variant (374×499 portrait) — the card's left column.
      # Mirrors the game detail card's cover: bounded to the 374×210 16:9 box
      # (.pito-video-linked-game-card__cover, shared CSS) with the Ken-Burns
      # vertical pan (.pito-cover-pan). Same variant as Pito::Game::DetailComponent.
      def cover_url
        Pito::ImagePath.call(@game.cover_art, variant: ::Game::DETAIL_COVER_VARIANT)
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

      # Price as coin glyphs + number ("🪙🪙🪙 59.99"), or the FREE star when
      # unpriced — html_safe. Surfaces in `show vid <id>` as an :enhanced message.
      def price_label
        Pito::Game::PriceGlyphs.html(@game.price)
      end
    end
  end
end
