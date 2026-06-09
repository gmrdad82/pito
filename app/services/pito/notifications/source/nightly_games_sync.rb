# Phase 24A — Nightly IGDB games sync summary notification.
#
# Called by `GameIgdbNightlyRefresh#perform` after the full batch completes.
# Always creates ONE Notification summarising the run regardless of outcome.
#
# The message is HTML — a bold summary line followed by an optional failures
# list. User-facing strings come from Pito::Copy so the copy guard stays green.
module Pito
  module Notifications
    module Source
      module NightlyGamesSync
        module_function

        # @param checked  [Integer] total games iterated
        # @param updated  [Integer] games whose DB row was written (updated_at advanced)
        # @param changed_titles [Array<String>] titles of updated games
        # @param failures [Array<Hash>] array of { title:, error: } for each failed game
        # @return [Notification]
        def report!(checked:, updated:, changed_titles:, failures:)
          message = build_message(checked: checked, updated: updated,
                                  changed_titles: changed_titles, failures: failures)

          Notification.create!(message: message)
        end

        # Builds the HTML message string.
        def build_message(checked:, updated:, changed_titles:, failures:)
          summary = Pito::Copy.render(
            "pito.copy.notifications.nightly_games_sync.summary",
            checked: checked, updated: updated
          )

          parts = [ "<strong>#{summary}</strong>" ]

          if changed_titles.any?
            titles_html = changed_titles.map { |t| "<li>#{CGI.escapeHTML(t)}</li>" }.join
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

          parts.join
        end
        private_class_method :build_message
      end
    end
  end
end
