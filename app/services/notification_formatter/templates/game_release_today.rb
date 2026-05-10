# Phase 16 §2 — Notification formatter.
#
# Template for the `game_release_today` notification kind.
# Same `event_payload` shape as `game_release_upcoming`.
module NotificationFormatter
  module Templates
    class GameReleaseToday < Base
      def title
        "#{fetch(:game_title, placeholder('game title'))} releases today"
      end

      def body
        title_text = fetch(:game_title, placeholder("game title"))
        platforms  = join_list(fetch(:platforms), fallback: "tbd")
        igdb       = fetch(:igdb_url)

        base = "#{title_text} is out today on #{platforms}."
        igdb.present? ? "#{base} [igdb](#{igdb})" : base
      end

      def url
        game_id = fetch(:game_id)
        return nil if game_id.blank?

        "/games/#{game_id}"
      end
    end
  end
end
