# Phase 25 — 01c (LD-13). Auth audit logger.
#
# Single entry point for writing `AuthAuditLog` rows. Every privileged
# auth action — approve / block / unblock / purge / TOTP enroll /
# disable / backup-code regenerate — funnels through here so the
# "what got logged" surface stays in one place across sub-specs.
#
# Contract:
#
#     Pito::Auth::AuditLogger.call(
#       acting_user: Current.user,
#       source_surface: :web | :tui | :mcp,
#       action: :approve | :block | :unblock | :purge |
#               :totp_enroll | :totp_disable | :backup_code_regenerate,
#       target: <ActiveRecord row> | nil,
#       target_type: String | nil,
#       target_id: Integer | nil,
#       metadata: { ... },
#     )
#
# Either `target:` (an AR record from which type + id are derived) OR
# the explicit `target_type:` + `target_id:` pair must be supplied.
# Missing inputs raise `ArgumentError` so a controller bug surfaces
# loudly rather than silently dropping the audit row.
#
# Invalid enum values (`source_surface` / `action`) also raise — the
# enum guards are strict by design (LD-13).
#
# The row write is NOT wrapped in its own transaction; callers should
# wrap their AuditLogger call inside the same transaction as the
# approve / block / unblock state change so the audit row and the
# domain mutation succeed-or-fail together.
module Pito
  module Auth
    class AuditLogger
      VALID_SURFACES = %i[web tui mcp].freeze
      # Post-Phase-25 rollback. The location-tied vocabulary
      # (`approve`, `block`, `unblock`, `purge`) is gone with the
      # new-location approval surface. The `AuthAuditLog` enum values
      # (`0..3`) stay RESERVED on the model — never renumber.
      # `youtube_credentials_updated` (value 7) is also RESERVED;
      # Phase 29 Unit A1 dropped the YouTube credentials Settings pane.
      # Active vocabulary covers TOTP lifecycle + Voyage credential
      # writes + password reset.
      VALID_ACTIONS  = %i[totp_enroll totp_disable
                          backup_code_regenerate
                          voyage_credentials_updated
                          password_reset].freeze

      def self.call(acting_user:, source_surface:, action:, target: nil,
                    target_type: nil, target_id: nil, metadata: {})
        raise ArgumentError, "acting_user required" if acting_user.nil?
        raise ArgumentError, "acting_user must persist" unless acting_user.respond_to?(:id) && acting_user.id.present?

        surface_sym = source_surface.to_sym
        unless VALID_SURFACES.include?(surface_sym)
          raise ArgumentError, "invalid source_surface: #{source_surface.inspect}"
        end

        action_sym = action.to_sym
        unless VALID_ACTIONS.include?(action_sym)
          raise ArgumentError, "invalid action: #{action.inspect}"
        end

        type, id = resolve_target!(target: target, target_type: target_type, target_id: target_id)

        AuthAuditLog.create!(
          acting_user: acting_user,
          source_surface: surface_sym,
          action: action_sym,
          target_type: type,
          target_id: id,
          metadata: (metadata || {}).deep_stringify_keys
        )
      end

      def self.resolve_target!(target:, target_type:, target_id:)
        if target
          [ target.class.name, target.id ]
        elsif target_type.present? && target_id.present?
          [ target_type.to_s, target_id.to_i ]
        else
          raise ArgumentError,
                "target (AR record) or target_type+target_id required"
        end
      end
    end
  end
end
