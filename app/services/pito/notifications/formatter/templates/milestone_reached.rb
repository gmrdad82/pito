# Notification formatter.
#
# Template for the `milestone_reached` notification kind.
#
# Required `event_payload` keys: `rule_id`, `rule_name`, `metric`,
# `threshold`, `metric_value_at_fire`, `scope_type`
# (`"install"` / `"channel"` / `"video"`), `scope_id` (nullable for
# install scope), `scope_label` (denormalized by §1's builder).
module Pito
  module Notifications
    module Formatter
      module Templates
        class MilestoneReached < Base
          def title
            "milestone: #{fetch(:rule_name, placeholder('rule name'))}"
          end

          def body
            metric    = fetch(:metric, placeholder("metric"))
            threshold = fetch(:threshold, placeholder("threshold"))
            value     = fetch(:metric_value_at_fire, placeholder("value"))
            scope     = scope_label

            "#{metric} crossed #{threshold} at #{value} on #{scope}."
          end

          def url
            cal_entry_id = notification.source_calendar_entry_id
            return nil if cal_entry_id.blank?

            "/calendar/entries/#{cal_entry_id}"
          end

          private

          def scope_label
            explicit = fetch(:scope_label)
            return explicit if explicit.present?

            case fetch(:scope_type).to_s
            when "install" then "this install"
            when "channel" then placeholder("channel")
            when "video"   then placeholder("video")
            else placeholder("scope")
            end
          end
        end
      end
    end
  end
end
