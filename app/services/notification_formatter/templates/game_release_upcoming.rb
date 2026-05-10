# Phase 16 §2 — Notification formatter.
#
# Template for the `game_release_upcoming` notification kind.
#
# Required `event_payload` keys: `game_id`, `game_title`, `release_date`
# (iso8601), `days_until` (int), `igdb_url` (nullable), `platforms`
# (array of strings, nullable).
module NotificationFormatter
  module Templates
    class GameReleaseUpcoming < Base
      def title
        title_text = fetch(:game_title, placeholder("game title"))
        days       = fetch(:days_until)

        if days.is_a?(Numeric) || days.to_s.match?(/\A\d+\z/)
          n = days.to_i
          unit = n == 1 ? "day" : "days"
          "#{title_text} releases in #{n} #{unit}"
        else
          "#{title_text} releases soon"
        end
      end

      def body
        title_text = fetch(:game_title, placeholder("game title"))
        release    = release_date_human
        platforms  = join_list(fetch(:platforms), fallback: "tbd")
        igdb       = fetch(:igdb_url)

        base = "#{title_text} launches on #{release} on #{platforms}."
        igdb.present? ? "#{base} [igdb](#{igdb})" : base
      end

      def url
        game_id = fetch(:game_id)
        return nil if game_id.blank?

        "/games/#{game_id}"
      end

      private

      # The spec body template references `<release_date_human>`. We
      # accept either an ISO date (`2026-05-17`) or a humanized string
      # already in the payload; if neither is present, fall back to a
      # placeholder. We never crash on a bad date string.
      def release_date_human
        raw = fetch(:release_date)
        return placeholder("release date") if raw.blank?

        Date.parse(raw.to_s).strftime("%b %-d, %Y")
      rescue ArgumentError, TypeError
        raw.to_s
      end
    end
  end
end
