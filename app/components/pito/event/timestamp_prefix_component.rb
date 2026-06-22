# frozen_string_literal: true

module Pito
  module Event
    # Inline "HH:MM " prefix that leads a message's first line — 24-hour, dim
    # (text-fg-faded), distinct from the message color. Renders nothing without a
    # timestamp. A single trailing space separates the time from the body copy;
    # there is no middot separator.
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
        # no-op when the value is already zoned to Time.zone.
        @timestamp.in_time_zone.strftime("%H:%M")
      end
    end
  end
end
