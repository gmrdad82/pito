# frozen_string_literal: true

# Daily check: for every YouTube connection still flagged `needs_reauth` (e.g.
# after a 401 / expired refresh token), drop a reminder Notification to reconnect.
#
# Idempotent via an unread-message match — while the reminder is still unread the
# job won't create a duplicate, so a perpetually-disconnected channel isn't spammed
# nightly. Reconnecting clears `needs_reauth`, so the reminders stop on their own.
class YoutubeReauthCheckJob < ApplicationJob
  queue_as :default

  def perform
    YoutubeConnection.where(needs_reauth: true).includes(:channels).find_each do |conn|
      Pito::Notifications::Source::YoutubeReauth.report!(conn)
    end
  end
end
