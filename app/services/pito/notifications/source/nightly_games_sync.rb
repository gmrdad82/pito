# Phase 24A / Phase 25A — Nightly IGDB games sync summary notification.
#
# Called by `GameIgdbNightlyRefresh#perform` after the full batch completes,
# but ONLY when there is something noteworthy (changed games, failures, or
# a game releasing within 30 days). Quiet runs produce no Notification.
#
# The message is HTML — a bold summary line followed by optional sections for
# changed titles, failures, and games releasing soon.
# User-facing strings come from Pito::Copy so the copy guard stays green.
module Pito
  module Notifications
    module Source
      module NightlyGamesSync
        module_function

        # @param checked       [Integer]          total games iterated
        # @param changed       [Array<String>]    titles of games whose DB row advanced
        # @param failures      [Array<Hash>]      array of { title:, error: } for each failed game
        # @param releasing_30d [Array<Hash>]      array of { title:, release_date: } releasing within 30 days
        # @return [Notification]
        def report!(checked:, changed:, failures:, releasing_30d:)
          message = build_message(
            checked:      checked,
            changed:      changed,
            failures:     failures,
            releasing_30d: releasing_30d
          )

          Notification.create!(message: message)
        end

        # Builds the HTML message string.
        def build_message(checked:, changed:, failures:, releasing_30d:)
          summary = Pito::Copy.render(
            "pito.copy.notifications.nightly_games_sync.summary",
            checked: checked, updated: changed.size
          )

          parts = [ "<strong>#{summary}</strong>" ]

          if changed.any?
            titles_html = changed.map { |t| "<li>#{CGI.escapeHTML(t)}</li>" }.join
            parts << "<ul>#{titles_html}</ul>"
          end

          if failures.any?
            failure_header = Pito::Copy.render(
              "pito.copy.notifications.nightly_games_sync.failures_header",
              count: failures.size
            )
            failure_items = failures.map { |f| "<li>#{CGI.escapeHTML(f[:title])}: #{CGI.escapeHTML(f[:error])}</li>" }.join
            parts << "<strong>#{failure_header}</strong><ul>#{failure_items}</ul>"
          end

          if releasing_30d.any?
            releasing_header = Pito::Copy.render(
              "pito.copy.notifications.nightly_games_sync.releasing_soon_header",
              count: releasing_30d.size
            )
            releasing_items = releasing_30d.map do |g|
              Pito::Copy.render(
                "pito.copy.notifications.nightly_games_sync.releasing_soon_item",
                title:        CGI.escapeHTML(g[:title]),
                release_date: CGI.escapeHTML(g[:release_date].to_s)
              )
            end.map { |line| "<li>#{line}</li>" }.join
            parts << "<strong>#{releasing_header}</strong><ul>#{releasing_items}</ul>"
          end

          parts.join
        end
        private_class_method :build_message
      end
    end
  end
end
