# frozen_string_literal: true

# Phase P9 — daily release-countdown reminder copy source.
#
# Given a game and how many days remain until its release, returns a witty
# one-line notification MESSAGE STRING drawn from the
# `pito.copy.notifications.release_countdown` dictionary (50 variants), with
# `%{n}` (days remaining) and `%{title}` interpolated.
#
# SCHEMA NOTE: the live `Notification` model is message-only
# (`[id, created_at, updated_at, message, read_at]`). This source therefore
# returns a plain String and nothing else — it does NOT create the record,
# does NOT use PayloadBuilder, and does NOT reference any dropped column
# (`event_type`, `dedup_key`, `kind`, `severity`). The caller
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
