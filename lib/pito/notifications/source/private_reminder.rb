# frozen_string_literal: true

module Pito
  module Notifications
    module Source
      # Nightly "you have private vids sitting around" reminder.
      #
      # Called by the nightly clock with the count of qualifying private vids
      # (privacy "private", unscheduled, uploaded more than a day ago — the
      # caller computes the count via `Video.private_unscheduled` + the
      # older-than-1-day rule; this source only reacts to the integer). A
      # count of zero means a quiet night — no Notification.
      #
      # The line comes from the `pito.copy.private_reminder` 50-variant
      # dictionary, interpolating `%{count}` and resolving the inline
      # `{singular|plural}` word choice (e.g. `{vid|vids}`) the dictionary uses
      # for natural-sounding counts. The push notification title ("Unpublished
      # vids") comes from the sibling 1-variant `pito.copy.private_reminder_title`
      # key and rides in the FCM payload as `data.title` (Pito::Fcm::Sender).
      #
      # == Once-per-calendar-day dedupe
      #
      # The `Notification` schema is message-only — no dedup_key column. We embed
      # an invisible, stable HTML-comment MARKER (`<!-- pito:private_reminder:
      # <iso-date> -->`) in each message and, before creating one, check whether a
      # notification carrying today's marker already exists — mirroring the
      # marker technique `ReleaseCountdownJob` uses for its own same-day dedup.
      # The comment is stripped by the sanitized panel render and by the webhook
      # formatter's tag-strip pass, so it never surfaces to the owner.
      module PrivateReminder
        module_function

        # @param count [Integer] qualifying private vids (0 = nothing to report)
        # @return [Notification, nil] the created notification, or nil when
        #   count is zero or a reminder for today already exists.
        def report!(count)
          return nil if count.to_i <= 0

          today = Date.current
          return nil if already_reported?(today)

          Notification.create!(
            message: build_message(count, today),
            level:   "warning",
            title:   Pito::Copy.render("pito.copy.private_reminder_title")
          )
        end

        def build_message(count, date)
          line = Pito::Copy.render("pito.copy.private_reminder", count: count)
          "#{resolve_plurals(line, count)}#{marker(date)}"
        end
        private_class_method :build_message

        # Resolves every inline `{singular|plural}` token against `count`.
        def resolve_plurals(string, count)
          string.gsub(/\{(\w+)\|(\w+)\}/) { count == 1 ? ::Regexp.last_match(1) : ::Regexp.last_match(2) }
        end
        private_class_method :resolve_plurals

        def marker(date)
          " <!-- pito:private_reminder:#{date.iso8601} -->"
        end
        private_class_method :marker

        def already_reported?(date)
          Notification
            .where(created_at: date.all_day)
            .where("message LIKE ?", "%#{marker(date)}%")
            .exists?
        end
        private_class_method :already_reported?
      end
    end
  end
end
