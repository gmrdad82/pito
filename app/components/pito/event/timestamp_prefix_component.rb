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
    # The three-tier rule itself lives in Pito::Formatter::HouseDate.stamp —
    # this was the original implementation the house format generalized from;
    # it now delegates so every other stamp on every other surface (SyncStamp
    # and whatever comes next) shares this ONE rule.
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
        # HouseDate renders in the app's local zone (in_time_zone — a no-op
        # when the value is already zoned to Time.zone) and reads "today" per
        # call, so a re-rendered event ages into the dated form.
        Pito::Formatter::HouseDate.stamp(@timestamp)
      end
    end
  end
end
