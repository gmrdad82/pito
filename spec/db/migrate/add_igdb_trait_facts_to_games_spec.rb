# frozen_string_literal: true

require "rails_helper"

# db/migrate files aren't autoloaded (not a Zeitwerk root) — require the one
# file this spec exercises directly.
require Rails.root.join("db/migrate/20260717010000_add_igdb_trait_facts_to_games.rb").to_s

# ── AddIgdbTraitFactsToGames — reversibility + shape ─────────────────────
#
# Mirrors spec/db/migrate/add_traits_to_games_spec.rb's approach: re-runs
# the SAME migration instance down then back up against the schema this
# whole suite already runs on, proving `change` genuinely reverses (not
# just parses).
RSpec.describe AddIgdbTraitFactsToGames do
  def assert_columns_present(connection)
    expect(connection.column_exists?(:games, :game_modes)).to be true
    expect(connection.column_exists?(:games, :hypes)).to be true
    expect(connection.column_exists?(:games, :age_ratings)).to be true

    game_modes = connection.columns(:games).find { |c| c.name == "game_modes" }
    expect(game_modes.sql_type).to eq("text")
    expect(game_modes.array?).to be true
    expect(game_modes.null).to be false
    expect(game_modes.default).to eq("{}") # postgres array-literal default syntax

    hypes = connection.columns(:games).find { |c| c.name == "hypes" }
    expect(hypes.sql_type).to eq("integer")
    expect(hypes.null).to be true

    age_ratings = connection.columns(:games).find { |c| c.name == "age_ratings" }
    expect(age_ratings.sql_type).to eq("jsonb")
    expect(age_ratings.null).to be false
    expect(age_ratings.default).to eq("{}")

    game_modes_index = connection.indexes(:games).find { |i| i.columns == [ "game_modes" ] }
    expect(game_modes_index).to be_present
    expect(game_modes_index.using).to eq(:gin)

    age_ratings_index = connection.indexes(:games).find { |i| i.columns == [ "age_ratings" ] }
    expect(age_ratings_index).to be_present
    expect(age_ratings_index.using).to eq(:gin)
  end

  it "adds an already-migrated game_modes/hypes/age_ratings shape with the pinned defaults/null/indexes" do
    assert_columns_present(ActiveRecord::Base.connection)
  end

  it "is reversible: down drops the columns + indexes, up restores them" do
    connection = ActiveRecord::Base.connection
    migration = described_class.new

    migration.migrate(:down)
    expect(connection.column_exists?(:games, :game_modes)).to be false
    expect(connection.column_exists?(:games, :hypes)).to be false
    expect(connection.column_exists?(:games, :age_ratings)).to be false
    expect(connection.indexes(:games).any? { |i| i.columns == [ "game_modes" ] }).to be false
    expect(connection.indexes(:games).any? { |i| i.columns == [ "age_ratings" ] }).to be false

    migration.migrate(:up)
    assert_columns_present(connection)
  end
end
