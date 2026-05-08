# frozen_string_literal: true

# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — OAuth audit log.
#
# Subscribes to Doorkeeper's `ActiveSupport::Notifications` events and
# writes one JSON line per event to the existing `log/auth_audit.log`
# file (shared with Phase 5 bearer-token audit and Phase 12 Step A
# session audit). Best-effort: failures inside the subscriber are
# swallowed so a logger glitch never breaks the request path.
ActiveSupport::Notifications.subscribe(/\A(create_token|refresh_token|revoke_token)\.doorkeeper\z/) do |name, _start, _finish, _id, payload|
  next unless defined?(AUTH_AUDIT_LOGGER)

  begin
    event = case name
    when "create_token.doorkeeper"  then "oauth.token.created"
    when "refresh_token.doorkeeper" then "oauth.token.refreshed"
    when "revoke_token.doorkeeper"  then "oauth.token.revoked"
    end

    token       = payload[:access_token] || payload[:token]
    application = payload[:application] || token&.application
    resource_owner_id =
      if token.respond_to?(:resource_owner_id)
        token.resource_owner_id
      else
        payload[:resource_owner_id]
      end

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: event,
      application_id: application&.id,
      application_name: application&.name,
      user_id: resource_owner_id,
      scopes: token&.scopes&.to_s,
      grant_type: payload[:grant_type]
    }.to_json)
  rescue StandardError
    # Audit logging must never break the request path.
    nil
  end
end
