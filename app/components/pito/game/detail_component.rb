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
      def initialize(game:, intro: nil)
        @game  = game
        @intro = intro
      end

      def cover_art_attached?
        @game.cover_art.attached?
      end

      def cover_art_url
        Pito::ImagePath.call(@game.cover_art, variant: ::Game::COVER_VARIANT)
      end

      # Larger 480px-wide cover variant for the detail card's left column.
      def detail_cover_url
        Pito::ImagePath.call(@game.cover_art, variant: ::Game::DETAIL_COVER_VARIANT)
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

      # Formatted footage hours ("5h", "12.5h"), or "—" when nil/zero — the
      # Footage row always renders, mirroring the Price row.
      def footage_label
        Pito::Formatter::FootageHours.call(@game.footage_hours)
      end

      # The price as coin glyphs + number ("🪙🪙🪙 59.99"), or the FREE star when
      # unpriced — html_safe. The Price row always renders, mirroring Footage.
      def price_label
        Pito::Game::PriceGlyphs.html(@game.price)
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
        @game.footage_hours
      end

      # ── Left-column stats (summed across all linked videos) ──────────────────

      # Stat counters (views · likes · comments) for Pito::Stats::CountersComponent,
      # summed across the game's linked videos.
      def stat_counter_metrics
        [
          { key: :views,    value: linked_video_totals[:views] },
          { key: :likes,    value: linked_video_totals[:likes] },
          { key: :comments, value: linked_video_totals[:comments] }
        ]
      end

      # The score bar and the TTB bar share one space-padded label width so their
      # `[` brackets line up. Both labels are generated ONCE here (Pito::Copy
      # picks a random witty variant per call) and ljust-padded to the longer of
      # the two — specific to THIS message, not a universal width.
      def score_bar_label
        bar_labels.fetch(:score)
      end

      def ttb_bar_label
        bar_labels.fetch(:ttb)
      end

      # Returns one Achievement per metric — the one with the highest threshold
      # (the last unlocked in that lane) — ordered by unlocked_at descending
      # so the most recently-advanced lane appears first.
      def top_shinies_per_metric
        @game.achievements
             .group_by(&:metric)
             .values
             .map { |a| a.max_by(&:threshold) }
             .sort_by { |a| -a.unlocked_at.to_i }
      end

      private

      def bar_labels
        @bar_labels ||= begin
          score = Pito::Copy.render("pito.copy.game.score_label").to_s
          ttb   = Pito::Copy.render("pito.copy.game.ttb_label").to_s
          width = [ score.length, ttb.length ].max
          { score: score.ljust(width), ttb: ttb.ljust(width) }
        end
      end

      # Single-pass sum over linked videos (avoids iterating the association
      # three times). Each stat reader may return nil (no row yet) → .to_i → 0.
      def linked_video_totals
        @linked_video_totals ||= @game.linked_videos.each_with_object(
          { views: 0, likes: 0, comments: 0 }
        ) do |v, totals|
          totals[:views]    += v.view_count.to_i
          totals[:likes]    += v.like_count.to_i
          totals[:comments] += v.comment_count.to_i
        end
      end
    end
  end
end
