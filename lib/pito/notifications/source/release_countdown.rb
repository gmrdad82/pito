# frozen_string_literal: true

# Daily release-countdown reminder copy source.
#
# Given a game, the platform(s) releasing on a date, and how many days remain,
# returns a witty one-line notification MESSAGE STRING drawn from the
# `pito.copy.notifications.release_countdown` dictionary (50 variants), with
# `%{n}` (days remaining), `%{title}`, and `%{platforms}` interpolated.
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
        # @param platforms      [String]  the platform label(s), e.g. "PlayStation + Steam"
        # @return [String] the interpolated, witty reminder line
        def message(game:, days_remaining:, platforms:)
          Pito::Copy.render(
            "pito.copy.notifications.release_countdown",
            n:         days_remaining,
            title:     game.title,
            platforms: platforms
          )
        end
      end
    end
  end
end
