# Phase 25 — 01a. Login attempt log. Every login POST writes one row
# regardless of outcome. Rows are durable — never auto-purged. Manual
# purge surfaces ship in 01d / 01f.
#
# `result` enum carries the locked LD-1 set; `pending_approval` is
# included for forward compatibility with 01b even though 01a only ever
# writes success / failed / blocked.
#
# `reason` enum carries the locked LD-1 set verbatim; values not yet
# written by 01a stay reserved for later sub-specs (2fa, approve flows,
# notifications, expiry).
class CreateLoginAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :login_attempts do |t|
      t.references :user, foreign_key: true, index: true
      t.citext :email_attempted
      t.integer :result, null: false
      t.inet :ip, null: false
      t.string :ip_prefix, null: false
      t.string :geo_city
      t.string :geo_region
      t.string :geo_country, limit: 2
      t.string :user_agent, null: false, limit: 1024
      t.string :browser
      t.string :os
      t.string :fingerprint_hash, null: false, limit: 64
      t.integer :reason, null: false
      t.references :notification, foreign_key: true, index: true
      t.bigint :approved_by_user_id
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :login_attempts, :created_at
    add_index :login_attempts, :result
    add_index :login_attempts, :email_attempted
    add_index :login_attempts, :fingerprint_hash
    add_index :login_attempts, [ :fingerprint_hash, :ip_prefix ],
              name: "index_login_attempts_on_fp_and_prefix"
    add_index :login_attempts, :approved_by_user_id

    add_foreign_key :login_attempts, :users,
                    column: :approved_by_user_id,
                    on_delete: :nullify
  end
end
