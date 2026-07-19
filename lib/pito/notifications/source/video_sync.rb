# Per-channel video-library sync summary notification.
#
# Called by `VideoImportJob#perform` and `VideoReconcileJob#perform` after the
# channel's `Pito::Sync::VideoLibrary` pass completes, but ONLY when the run
# changed something (imported, updated, or deleted at least one video). A quiet
# run — nothing imported, updated, or deleted — produces no Notification.
#
# The message is HTML — a bold one-line summary followed by an optional short
# list of the imported/deleted titles (capped, with a "+ K more" tail).
# The summary line comes from `Pito::Copy` so the copy guard stays green; the
# titles list is plain HTML with each title escaped.
module Pito
  module Notifications
    module Source
      module VideoSync
        module_function

        # Cap on how many titles to enumerate before collapsing to "+ K more".
        TITLES_CAP = 10

        # @param scope_label [String]                a channel handle / label for the summary line
        # @param result      [Pito::Sync::VideoLibrary::Result]
        # @return [Notification, nil] the Notification, or nil on a quiet run
        def report!(scope_label:, result:)
          return nil if (result.imported + result.updated + result.deleted).zero?

          Notification.create!(
            message: build_message(scope_label:, result:),
            level:   "success",
            title:   Pito::Copy.render("pito.copy.notifications.video_sync_title")
          )
        end

        # Builds the HTML message string.
        def build_message(scope_label:, result:)
          summary = Pito::Copy.render(
            "pito.copy.videos.sync_summary",
            label:    scope_label,
            imported: result.imported,
            updated:  result.updated,
            deleted:  result.deleted
          )

          parts = [ "<strong>#{summary}</strong>" ]

          titles = result.titles.to_a
          parts << titles_list(titles) if titles.any?

          parts.join
        end
        private_class_method :build_message

        # Renders up to TITLES_CAP titles as an HTML list, collapsing any
        # overflow into a trailing "+ K more" item. Each title is escaped.
        def titles_list(titles)
          shown = titles.first(TITLES_CAP)
          items = shown.map { |t| "<li>#{CGI.escapeHTML(t.to_s)}</li>" }

          remaining = titles.size - shown.size
          items << "<li>+ #{remaining} more</li>" if remaining.positive?

          "<ul>#{items.join}</ul>"
        end
        private_class_method :titles_list
      end
    end
  end
end
