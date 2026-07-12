# frozen_string_literal: true

module Pito
  module Event
    # Inline timestamp prefix that leads a message's first line — 24-hour, dim
    # (text-fg-faded), distinct from the message color. Today's messages show
    # bare "HH:MM "; older messages carry their day ("6 Jul 11:04", plus the
    # year once it differs — "2 Jan '25 11:04", the badge/chart-tick month
    # shape) so a days-old conversation never reads like it happened today.
    # Renders nothing without a timestamp. A single trailing space separates
    # the time from the body copy; there is no middot separator.
    #
    # Rendered via #call (not a template) so there is NO trailing newline — a
    # template's trailing "\n" collapses to a stray space between the prefix and
    # the message body.
    class TimestampPrefixComponent < ViewComponent::Base
      def initialize(timestamp:)
        @timestamp = timestamp
      end

      def render?
        @timestamp.present?
      end

      def call
        tag.span(class: "pito-timestamp-prefix text-fg-faded") do
          "#{formatted_timestamp} "
        end
      end

      private

      def formatted_timestamp
        # Render in the request's configured zone (Time.zone) so a UTC-stored
        # timestamp shows the user's local wall-clock time. in_time_zone is a
        # no-op when the value is already zoned to Time.zone. Today is read
        # per render, so a re-rendered event ages into the dated form.
        local = @timestamp.in_time_zone
        today = Time.zone.today

        if local.to_date == today
          local.strftime("%H:%M")
        elsif local.year == today.year
          local.strftime("%-d %b %H:%M")
        else
          local.strftime("%-d %b '%y %H:%M")
        end
      end
    end
  end
end
