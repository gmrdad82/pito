# Auth audit log row.
#
# Every privileged auth action (TOTP enroll / disable, backup-code
# regenerate, Voyage credential rotation, password reset) writes one
# row via `Pito::Auth::AuditLogger`. The row is the canonical "who did
# what, from where, to which target" record. Never auto-pruned.
#
# `source_surface` enum (`web` / `tui` / `mcp`) records where the
# action originated so a TOTP disable from a CLI in-TUI overlay vs an
# MCP tool is durable in the audit trail.
#
# `target_type` + `target_id` are a polymorphic pointer (NOT a
# `belongs_to :target, polymorphic: true` — the polymorphic
# association would create accidental dependent-destroy paths and we
# never want the audit row to follow the target into deletion). The
# target is usually `User` (TOTP enroll / disable / backup-code
# regenerate / password reset) or `AppSetting` (Voyage credential
# rotation).
#
# Post-Phase-25 rollback: the new-location approval vocabulary
# (`approve`, `block`, `unblock`, `purge`) and the
# `LoginAttempt` / `BlockedLocation` polymorphic targets are gone
# along with the corresponding controllers and services.
#
# `metadata` is a free-form jsonb bag for sub-spec-specific extras
# (e.g., the resolved fingerprint short hash, the IP prefix, the
# attempt id when the target is a session, etc.). Keys are strings.
class AuthAuditLog < ApplicationRecord
  belongs_to :acting_user,
             class_name: "User",
             foreign_key: :acting_user_id

  # Rails 8.1 — defensive: lock the enum-backing column types so
  # autoload races / bootsnap cache cannot trip the
  # `Undeclared attribute type for enum` failure path.
  attribute :source_surface, :integer
  attribute :action, :integer

  enum :source_surface, {
    web: 0,
    tui: 1,
    mcp: 2
  }, prefix: :source

  # Post-Phase-25 rollback: the location-tied vocabulary
  # (`approve`, `block`, `unblock`, `purge`) dropped from the active
  # allowlist along with the new-location approval surface. Their
  # integer enum values (`0..3`) stay RESERVED — enum values are
  # durable, do not renumber.
  #
  # Phase 29 Unit A1 dropped the YouTube credentials Settings pane, so
  # `youtube_credentials_updated` (value 7) is no longer emitted by
  # any code path — also RESERVED. `voyage_credentials_updated` stays
  # active: the slimmed Voyage pane emits it on the
  # `voyage_index_project_notes` flag write via
  # `SettingsController#update_voyage`.
  #
  # Phase 29 — Unit A2 — `password_reset` (value 9). Written by
  # `PasswordResetsController#update` on a successful reset-via-2FA.
  enum :action, {
    totp_enroll: 4,
    totp_disable: 5,
    backup_code_regenerate: 6,
    voyage_credentials_updated: 8,
    password_reset: 9
  }, prefix: :action

  validates :acting_user_id, presence: true
  validates :source_surface, presence: true
  validates :action, presence: true
  validates :target_type, presence: true
  validates :target_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_target,
        ->(type, id) {
          where(target_type: type.to_s, target_id: id)
        }
  scope :for_acting_user, ->(user) { where(acting_user_id: user&.id) }
  scope :since, ->(ts) { where(arel_table[:created_at].gteq(ts)) }
end
