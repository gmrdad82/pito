# frozen_string_literal: true

require "rails_helper"

# db/migrate files aren't autoloaded (not a Zeitwerk root) — require the one
# file this spec exercises directly.
require Rails.root.join("db/migrate/20260717000001_add_traits_to_games.rb").to_s

# ── AddTraitsToGames — reversibility + shape ─────────────────────────────
#
# The migration already ran to build the schema this whole suite runs
# against (games.traits exists per db/schema.rb) — this spec re-runs the
# SAME migration instance down then back up, proving `change` genuinely
# reverses (not just parses) rather than trusting `add_column`/`add_index`
# invertibility on faith.
#
# Runs inside the outer per-example transaction (rails_helper's
# `use_transactional_fixtures`). Rails marks that transaction non-joinable,
# so the migration's own internal `connection.transaction` (every
# `use_transaction?` migration wraps in one) becomes a real SAVEPOINT and
# unwinds cleanly with the rest of the example — no separate cleanup needed.
RSpec.describe AddTraitsToGames do
  it "adds an already-migrated jsonb column with the pinned default/null/index" do
    connection = ActiveRecord::Base.connection

    expect(connection.column_exists?(:games, :traits)).to be true

    column = connection.columns(:games).find { |c| c.name == "traits" }
    expect(column.sql_type).to eq("jsonb")
    expect(column.null).to be false
    expect(column.default).to eq("{}")

    index = connection.indexes(:games).find { |i| i.columns == [ "traits" ] }
    expect(index).to be_present
    expect(index.using).to eq(:gin)
  end

  it "is reversible: down drops the column + index, up restores them" do
    connection = ActiveRecord::Base.connection
    migration = described_class.new

    migration.migrate(:down)
    expect(connection.column_exists?(:games, :traits)).to be false
    expect(connection.indexes(:games).any? { |i| i.columns == [ "traits" ] }).to be false

    migration.migrate(:up)
    expect(connection.column_exists?(:games, :traits)).to be true

    column = connection.columns(:games).find { |c| c.name == "traits" }
    expect(column.sql_type).to eq("jsonb")
    expect(column.null).to be false
    expect(column.default).to eq("{}")

    index = connection.indexes(:games).find { |i| i.columns == [ "traits" ] }
    expect(index).to be_present
    expect(index.using).to eq(:gin)
  end
end
