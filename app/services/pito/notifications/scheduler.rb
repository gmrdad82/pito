# Notifications data model + delivery channels.
#
# Cron-driven scheduler. Walks the calendar for ripe declarations
# (per `Pito::Calendar::NotificationDispatchDeclaration`),
# materializes one Notification row per declaration, then enqueues a
# `NotificationDeliver` per enabled channel.
#
# Idempotency posture: `(event_type, source_calendar_entry_id, fires_at)`
# is unique (partial index on `notifications`). The scheduler uses
# `find_or_create_by!` so re-runs in the same minute are safe; only
# the create path enqueues deliveries (the find path is a no-op).
module Pito
  module Notifications
    class Scheduler
      # How far ahead of `fires_at` we're willing to materialize a row.
      WINDOW = 5.minutes

      def perform
        materialize_calendar_declarations
        materialize_occurred_calendar_entries
      end

      private

      def materialize_calendar_declarations
        horizon = Time.current + WINDOW
        relevant_types = %i[
          game_release video_scheduled milestone_auto
        ]

        CalendarEntry
          .where(state: %i[scheduled occurred])
          .where(entry_type: relevant_types)
          .find_each do |entry|
            Pito::Calendar::NotificationDispatchDeclaration
              .declarations_for(entry)
              .each do |decl|
                next if decl[:fires_at] > horizon
                ensure_calendar_row!(
                  event_type: decl[:kind],
                  kind: kind_for(decl[:kind]),
                  severity: decl[:severity],
                  fires_at: decl[:fires_at],
                  source_calendar_entry: entry
                )
              end
          end
      end

      # The OccurredFlipper flips `:scheduled` entries to `:occurred`
      # once `starts_at` has passed. For `milestone_manual` and `custom`
      # entries, that flip IS the notification trigger — we materialize a
      # `calendar_entry_firing` row exactly once per entry.
      def materialize_occurred_calendar_entries
        CalendarEntry
          .where(entry_type: %i[milestone_manual custom])
          .where(state: :occurred)
          .where("starts_at <= ?", Time.current)
          .where.not(
            id: Notification
                  .where(event_type: "calendar_entry_firing")
                  .select(:source_calendar_entry_id)
          )
          .find_each do |entry|
            ensure_calendar_row!(
              event_type: "calendar_entry_firing",
              kind: :calendar_entry_firing,
              severity: :info,
              fires_at: entry.starts_at,
              source_calendar_entry: entry
            )
          end
      end

      def ensure_calendar_row!(event_type:, kind:, severity:, fires_at:,
                               source_calendar_entry:)
        payload = Pito::Notifications::PayloadBuilder.build(
          event_type: event_type,
          calendar_entry: source_calendar_entry,
          overrides: { title: payload_title_for(event_type, source_calendar_entry) }
        )

        notification = Notification.find_or_create_by!(
          event_type: event_type,
          source_calendar_entry_id: source_calendar_entry.id,
          fires_at: fires_at
        ) do |n|
          n.kind = kind
          n.severity = severity_value(severity)
          n.title = payload[:title]
          n.body = payload[:body]
          n.url = payload[:url]
          n.event_payload = payload[:event_payload]

          # Convenience pointer for `milestone_reached` — saves a join.
          if source_calendar_entry.respond_to?(:milestone_rule_id) &&
             source_calendar_entry.milestone_rule_id.present?
            n.source_milestone_rule_id = source_calendar_entry.milestone_rule_id
          end
        end

        enqueue_deliveries(notification) if notification.previously_new_record?
      end

      def enqueue_deliveries(notification)
        NotificationDeliver.perform_later(notification.id, "in_app")
        NotificationDeliver.perform_later(notification.id, "discord") if AppSetting.discord_delivery_enabled?
        NotificationDeliver.perform_later(notification.id, "slack")   if AppSetting.slack_delivery_enabled?
      end

      # Spec 02 will replace this with a per-event-type renderer. For Spec
      # 01 we use the entry title as a sane default so the inbox row is
      # human-readable.
      def payload_title_for(event_type, entry)
        case event_type
        when "game_release_today"
          "released today: #{entry.title}"
        when "milestone_reached"
          "milestone reached: #{entry.title}"
        when "calendar_entry_firing"
          entry.title
        when "video_scheduled_publishing_soon"
          "publishing soon: #{entry.title}"
        else
          event_type.to_s.tr("_", " ")
        end
      end

      # Map a declaration `kind` (string) to the Notification enum symbol.
      # The declaration uses kinds that map 1:1 onto the Notification
      # enum, with one exception: `video_scheduled_publishing_soon`
      # falls outside the notification enum (it ships a
      # `video_published` kind for the post-publish row only). Treat it as
      # a `calendar_entry_firing` kind so the scheduler still materializes
      # a row; the formatter (Spec 02) decides the rendering.
      def kind_for(decl_kind)
        case decl_kind.to_s
        when "video_scheduled_publishing_soon" then :calendar_entry_firing
        when "game_release_today"              then :game_release_today
        when "milestone_reached"               then :milestone_reached
        when "video_published"                 then :video_published
        when "calendar_entry_firing"           then :calendar_entry_firing
        else
          :calendar_entry_firing
        end
      end

      # `Pito::Calendar::NotificationDispatchDeclaration` returns severities
      # as strings ("info" / "warn" / "success" / "urgent"). The Notification
      # enum accepts the symbol form; coerce defensively.
      def severity_value(severity)
        severity.to_s.to_sym
      end
    end
  end
end
