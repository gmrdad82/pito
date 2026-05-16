# Post-Phase-25 rollback. Drop the entire new-location approval
# surface + the LoginAttempt forensic table.
#
# - `blocked_locations`        — auto-block list (3-strike pair-block).
# - `trusted_locations`        — per-user known fingerprint+ip_prefix pairs.
# - `login_attempts`           — per-attempt forensic log.
# - `sessions.approval_required_until` — pending-approval countdown column.
#
# `sessions.state` is a Rails integer-backed enum. The value
# `pending_approval = 1` was used in code only; no separate Postgres
# enum type to alter. The model drops the symbol from its `enum`
# declaration and the value stays RESERVED so a column read of `1`
# on any legacy row would be silently ignored (no production rows
# carry that value at the time of this drop — the consolidated
# beta_migration_3 created the column on a fresh schema).
#
# `auth_audit_logs.action` and `.source_surface` are also Rails
# integer-backed enums (no Postgres enum types). The model drops the
# location-action symbols from its `enum` declaration; the integer
# values (`approve = 0`, `block = 1`, `unblock = 2`, `purge = 3`)
# stay RESERVED.
class DropLocationsAndLoginAttempts < ActiveRecord::Migration[8.1]
  def change
    drop_table :login_attempts do |t|
      t.bigint   :approved_by_user_id
      t.string   :browser
      t.datetime :created_at, null: false
      t.citext   :email_attempted
      t.string   :fingerprint_hash, limit: 64, null: false
      t.string   :geo_city
      t.string   :geo_country, limit: 2
      t.string   :geo_region
      t.inet     :ip, null: false
      t.string   :ip_prefix, null: false
      t.bigint   :notification_id
      t.string   :os
      t.integer  :reason, null: false
      t.datetime :resolved_at
      t.integer  :result, null: false
      t.bigint   :session_id
      t.datetime :updated_at, null: false
      t.string   :user_agent, limit: 1024, null: false
      t.bigint   :user_id
      t.index [ :approved_by_user_id ], name: "index_login_attempts_on_approved_by_user_id"
      t.index [ :created_at ], name: "index_login_attempts_on_created_at"
      t.index [ :email_attempted ], name: "index_login_attempts_on_email_attempted"
      t.index [ :fingerprint_hash, :ip_prefix ], name: "index_login_attempts_on_fp_and_prefix"
      t.index [ :fingerprint_hash ], name: "index_login_attempts_on_fingerprint_hash"
      t.index [ :notification_id ], name: "index_login_attempts_on_notification_id"
      t.index [ :result ], name: "index_login_attempts_on_result"
      t.index [ :session_id ], name: "index_login_attempts_on_session_id"
      t.index [ :user_id ], name: "index_login_attempts_on_user_id"
    end

    drop_table :trusted_locations do |t|
      t.datetime :created_at, null: false
      t.string   :fingerprint_hash, limit: 64, null: false
      t.string   :ip_prefix, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :updated_at, null: false
      t.bigint   :user_id, null: false
      t.index [ :last_seen_at ], name: "index_trusted_locations_on_last_seen_at"
      t.index [ :user_id, :fingerprint_hash, :ip_prefix ],
              name: "index_trusted_locations_unique_triple",
              unique: true
      t.index [ :user_id ], name: "index_trusted_locations_on_user_id"
    end

    drop_table :blocked_locations do |t|
      t.datetime :blocked_at, null: false
      t.bigint   :blocked_by_user_id, null: false
      t.datetime :created_at, null: false
      t.string   :fingerprint_hash, limit: 64, null: false
      t.string   :ip_prefix, null: false
      t.integer  :source_surface, null: false
      t.jsonb    :metadata, default: {}, null: false
      t.datetime :unblocked_at
      t.bigint   :unblocked_by_user_id
      t.datetime :updated_at, null: false
      t.index [ :blocked_by_user_id ],
              name: "index_blocked_locations_on_blocked_by_user_id"
      t.index [ :fingerprint_hash, :ip_prefix ],
              name: "index_blocked_locations_unique_pair",
              unique: true
      t.index [ :unblocked_at ],
              name: "index_blocked_locations_on_unblocked_at"
    end

    remove_index :sessions, name: "index_sessions_on_approval_required_until" if index_exists?(:sessions, :approval_required_until, name: "index_sessions_on_approval_required_until")
    remove_column :sessions, :approval_required_until, :datetime
  end
end
