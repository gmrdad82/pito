# frozen_string_literal: true

module Pito
  module Video
    # Formats a duration in seconds as `M:SS` (under an hour) or `H:MM:SS`.
    # Minutes/seconds are zero-padded to two digits except the leading unit.
    #
    #   DurationFormat.call(574)  # => "9:34"
    #   DurationFormat.call(2603) # => "43:23"
    #   DurationFormat.call(3742) # => "1:02:22"
    #   DurationFormat.call(3632) # => "1:00:32"
    #
    # Returns nil for a blank or negative input.
    module DurationFormat
      module_function

      # @param seconds [Integer, nil]
      # @return [String, nil]
      def call(seconds)
        return nil unless seconds.present? && seconds >= 0

        hours   = seconds / 3600
        minutes = (seconds % 3600) / 60
        secs    = seconds % 60

        if hours.positive?
          format("%d:%02d:%02d", hours, minutes, secs)
        else
          format("%d:%02d", minutes, secs)
        end
      end
    end
  end
end
