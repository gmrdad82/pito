# frozen_string_literal: true

module Pito
  module Channel
    # The channel's linked-games grid: every game linked to the
    # channel's videos as a cover card — strip cover, then #id (left) and the
    # per-channel vid count (right, flush with the cover's right edge). No
    # title, no score bar (owner spec). Cards are 180px like the similar-games
    # strip, 5 per row in the conversation column, wrapping naturally.
    #
    # Games sort ALPHABETICALLY; the vid count is scoped to THIS channel's
    # videos only ("how much of this channel is that game"), not the game's
    # global link count.
    class GamesComponent < ViewComponent::Base
      def initialize(channel:)
        @channel = channel
      end

      def intro
        # games is a GROUPED relation — .size/.count would return a Hash
        # ({game_id => n}); .length loads the records and counts them.
        # tally = the count WITH its pluralized noun ("1 game" / "23 games") —
        # the dictionary can't pluralize a literal, so count-bound nouns
        # interpolate the pair (e.g. "spans 1 games").
        count = games.length
        Pito::Copy.render_html(
          "pito.copy.channels.games_intro",
          { count: count,
            tally: "#{count} #{count == 1 ? 'game' : 'games'}",
            title: @channel.title },
          shimmer: [ :title ]
        )
      end

      # The channel's linked games, alphabetical, each carrying its
      # per-channel link count as `channel_vids_count`.
      def games
        @games ||= ::Game
          .joins(video_game_links: :video)
          .where(videos: { channel_id: @channel.id })
          .group("games.id")
          .order(:title)
          .select("games.*, COUNT(video_game_links.id) AS channel_vids_count")
      end

      # "23 vids" / "1 vid" — the canonical noun, pluralized by count.
      def vids_label(game)
        count = game[:channel_vids_count]
        "#{count} #{count == 1 ? 'vid' : 'vids'}"
      end

      # Host-less ActiveStorage proxy path for the cover variant, or nil when
      # no attachment (the view falls back to the placeholder).
      def cover_art_url_for(game)
        Pito::ImagePath.call(game.cover_art, variant: :strip)
      end
    end
  end
end
