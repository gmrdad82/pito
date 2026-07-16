# frozen_string_literal: true

module Pito
  module Notifications
    module Source
      # Notification for a freshly-imported, still-unlinked video that scored
      # at least one game-link candidate (`Video::GameLinkSuggester`).
      #
      # Called by `LinkSuggestionJob` — a cron/background (sync-time) context
      # with no live turn to append a scrollback message to, so a Notification
      # is the surface (mirrors `VideoSync`/`NightlyGamesSync`). The caller
      # stamps `link_suggested_at` before calling `report!`, so this fires at
      # most once per video.
      #
      # The message is HTML — a bold heading naming the vid, followed by an
      # ordered list of candidates rendered as ready-to-run
      # `link vid <video_id> to game <game_id>` commands the operator can
      # paste straight into the chatbox to confirm (or ignore).
      module LinkSuggestion
        module_function

        # @param video [Video]        the freshly-imported, unlinked video
        # @param games [Array<Game>]  ranked candidates, `Video::GameLinkSuggester.call(video)`
        # @return [Notification]
        def report!(video:, games:)
          Notification.create!(message: build_message(video:, games:), level: "info")
        end

        # Builds the HTML message string.
        def build_message(video:, games:)
          heading = Pito::Copy.render(
            "pito.copy.notifications.link_suggestion.heading",
            title: CGI.escapeHTML(video.title.to_s)
          )

          items = games.each_with_index.map do |game, index|
            line = Pito::Copy.render(
              "pito.copy.notifications.link_suggestion.item",
              rank:     index + 1,
              game:     CGI.escapeHTML(game.title.to_s),
              video_id: video.id,
              game_id:  game.id
            )
            "<li>#{line}</li>"
          end.join

          "<strong>#{heading}</strong><ul>#{items}</ul>"
        end
        private_class_method :build_message
      end
    end
  end
end
