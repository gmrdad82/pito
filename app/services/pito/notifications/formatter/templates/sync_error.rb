# Notification formatter.
#
# Template for the `sync_error` notification kind.
#
# Required `event_payload` keys: `job_class`, `error_class`,
# `error_message`.
module Pito
  module Notifications
    module Formatter
      module Templates
        class SyncError < Base
          def title
            "sync error: #{fetch(:job_class, placeholder('job class'))}"
          end

          def body
            klass = fetch(:error_class, placeholder("error class"))
            msg   = fetch(:error_message, placeholder("error message"))
            "#{klass}: #{msg}"
          end

          def url
            # Per spec — the in-app inbox detail page. Notification id is
            # carried via the row.
            return nil if notification.id.blank?

            "/notifications/#{notification.id}"
          end
        end
      end
    end
  end
end
