# Beta 4 — Phase F1 Lane A. Status-bar cable channel.
#
# Single global channel that streams ALL top-status-bar updates: sync
# state + Sidekiq queue depths (busy / enqueued / retry / scheduled).
# The status bar is install-wide (not per-user), so subscribers all
# join the same `pito:status_bar` broadcasting — see ADR 0017's
# channel-naming convention (`pito:<section>:<panel>`; status bar is
# global so no scope suffix).
#
# Auth: `ApplicationCable::Connection` identifies by `current_user`,
# so we reject subscriptions when no user is attached (the connection
# layer already rejects truly unauthenticated cable clients; this is a
# belt-and-braces guard for tests / future paths that stub the
# connection identity to `nil`).
class StatusBarChannel < ApplicationCable::Channel
  BROADCAST_NAME = "pito:status_bar".freeze

  def subscribed
    return reject unless current_user.present?

    stream_from BROADCAST_NAME
  end

  def unsubscribed
    stop_all_streams
  end
end
