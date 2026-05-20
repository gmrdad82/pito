# Beta 4 — Phase F1 Lane A. ActionCable connection auth.
#
# Identifies the cable connection by `current_user` so per-panel
# channels can authorize subscriptions (e.g. `StatusBarChannel`
# rejects unauthenticated subscribers; future per-channel /per-game
# scoped channels will use the same identity to enforce ownership).
#
# Auth path mirrors the HTTP layer (`Sessions::AuthConcern`): the
# signed `:pito_session` cookie carries a session plaintext;
# `Sessions::Authenticator` resolves it to a `Session` record; the
# session's `user` becomes the cable identity.
#
# Pito remains a single-install multi-user app (ADR 0003), so this
# identity is for AUTH GATING only — not for data scoping. Channels
# that broadcast install-wide snapshots (e.g. `StackStatsChannel`)
# still stream from a single global broadcasting; the connection-level
# `identified_by :current_user` simply gives every channel a uniform
# hook to reject unauthenticated clients.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      result = Sessions::Authenticator.call(request)
      return reject_unauthorized_connection unless result.success?

      user = result.session.user
      return reject_unauthorized_connection unless user

      user
    end
  end
end
