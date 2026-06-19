# frozen_string_literal: true

# Daily release-countdown reminder copy source.
#
# Given a game and how many days remain until its release, returns a witty
# one-line notification MESSAGE STRING drawn from the
# `pito.copy.notifications.release_countdown` dictionary (50 variants), with
# `%{n}` (days remaining) and `%{title}` interpolated.
#
# Returns a plain String — does NOT create the record. The caller
# (`ReleaseCountdownJob`) does `Notification.create!(message:)`.
module Pito
  module Notifications
    module Source
      module ReleaseCountdown
        module_function

        # @param game           [Game]    the upcoming game
        # @param days_remaining [Integer] whole days from today until release
        # @return [String] the interpolated, witty reminder line
        def message(game:, days_remaining:)
          Pito::Copy.render(
            "pito.copy.notifications.release_countdown",
            n:     days_remaining,
            title: game.title
          )
        end
      end
    end
  end
end
