# Phase 25 — 01c (LD-13). Auth audit log row.
#
# Every privileged auth action (approve / block / unblock / purge /
# TOTP enroll / TOTP disable / backup-code regenerate) writes one row
# via `Auth::AuditLogger`. The row is the canonical "who did what,
# from where, to which target" record — distinct from `LoginAttempt`
# (which is per-attempt). Never auto-pruned.
#
# `source_surface` enum (`web` / `tui` / `mcp`) mirrors
# `BlockedLocation#source_surface` so an approve from a CLI in-TUI
# overlay vs an approve from the MCP tool is durable in the audit
# trail.
#
# `action` enum is the LD-13 vocabulary. The 01c sub-spec only
# writes `approve` and `block`; the other values are pre-declared so
# 01d / 01e / 01f need no further migration.
#
# `target_type` + `target_id` are a polymorphic pointer (NOT a
# `belongs_to :target, polymorphic: true` — the polymorphic
# association would create accidental dependent-destroy paths and we
# never want the audit row to follow the target into deletion). The
# target is the row the action was performed on: usually a
# `LoginAttempt` (approve / block / pending-resolve), sometimes a
# `BlockedLocation` (unblock / purge), or `User` (TOTP enroll /
# disable / backup-code regenerate).
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

  # LD-13 full vocabulary. 01c writes `approve` and `block`. The other
  # values are pre-declared so 01d–01f land without another migration.
  #
  # 2026-05-11 F3 — added two credential-rotation actions. Phase 29
  # Unit A1 dropped the YouTube credentials Settings pane, so
  # `youtube_credentials_updated` (value 7) is no longer emitted by
  # any code path — the enum value stays RESERVED (durable; never
  # renumber). `voyage_credentials_updated` stays active: the slimmed
  # Voyage pane emits it on the `voyage_index_project_notes` flag
  # write via `SettingsController#update_voyage`. `target_type` is
  # `AppSetting` (singleton row); `metadata` carries `changed_fields`
  # — the list of column names that mutated, never the values.
  #
  # Phase 29 — Unit A2 — added `password_reset` (value 9). Written by
  # `PasswordResetsController#update` on a successful reset-via-2FA.
  # `target` is the `User` whose password was reset; `metadata`
  # carries `reset_user_id`. Integer-backed enum — the new value
  # needs no migration.
  enum :action, {
    approve: 0,
    block: 1,
    unblock: 2,
    purge: 3,
    totp_enroll: 4,
    totp_disable: 5,
    backup_code_regenerate: 6,
    youtube_credentials_updated: 7,
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
