# Phase 29 — Unit A2. User auth refactor: drop `email`, add `username`.
#
# pito does not run SMTP, so `email` backed no notifications and gated
# no recovery flow — it was dead weight carrying account-existence
# risk and an email-format contract. This migration drops `email` and
# its unique index, and adds `username` (citext, NOT NULL, unique).
#
# Destructive-and-reseed posture (ADR 0003 / docs/setup.md): there is
# no production data, so the canonical recovery path stays
# `bin/rails db:drop db:create db:migrate db:seed`. The migration is
# nonetheless written to survive a non-empty `users` table — it adds
# `username` nullable, backfills a deterministic `user_<id>`
# placeholder for any existing row, then applies the NOT NULL
# constraint. A dev DB with a stale owner row reseeds cleanly on the
# next `db:seed`; the backfill placeholder is just a bridge so the
# migration itself never aborts mid-flight.
class SwapUserEmailForUsername < ActiveRecord::Migration[8.1]
  def up
    remove_index  :users, name: "index_users_on_email"
    remove_column :users, :email
    add_column    :users, :username, :citext

    # Backfill any pre-existing row with a deterministic placeholder so
    # the NOT NULL constraint below applies cleanly. On the canonical
    # destructive-and-reseed path the table is empty and this is a
    # no-op.
    execute(<<~SQL.squish)
      UPDATE users SET username = 'user_' || id WHERE username IS NULL
    SQL

    change_column_null :users, :username, false
    add_index :users, :username, unique: true,
              name: "index_users_on_username"
  end

  def down
    remove_index  :users, name: "index_users_on_username"
    remove_column :users, :username
    add_column    :users, :email, :citext, null: false
    add_index     :users, :email, unique: true,
                  name: "index_users_on_email"
  end
end
