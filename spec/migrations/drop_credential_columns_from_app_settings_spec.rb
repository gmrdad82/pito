require "rails_helper"
require Rails.root.join(
  "db/migrate/20260514170000_drop_credential_columns_from_app_settings.rb"
)

# Phase 29 — Unit A1. Drives the column-drop migration up and down on
# the live test DB to prove the seven secret-bearing / orphaned columns
# are removed and that `down` restores them (reversibility). The
# `around` hook leaves the test DB in the post-migration (dropped)
# state regardless of mid-example failure so neighbour specs keep
# working.
RSpec.describe DropCredentialColumnsFromAppSettings, type: :model do
  DROPPED_COLUMNS = %w[
    voyage_api_key
    youtube_api_key
    youtube_client_id
    youtube_client_secret
    youtube_redirect_uri
    slack_enabled
    discord_enabled
  ].freeze

  def column_for(name)
    ActiveRecord::Base.connection.columns(:app_settings).find { |c| c.name == name.to_s }
  end

  def any_dropped_column_present?
    DROPPED_COLUMNS.any? { |name| column_for(name) }
  end

  describe "post-migration state" do
    it "has dropped all seven credential / dead columns" do
      DROPPED_COLUMNS.each do |name|
        expect(column_for(name)).to be_nil, "expected #{name} to be dropped"
      end
    end

    it "keeps the surviving non-secret columns intact" do
      %w[key value voyage_index_project_notes keyboard_navigation_enabled timezone].each do |name|
        expect(column_for(name)).not_to be_nil, "expected #{name} to survive"
      end
    end
  end

  describe "rollback + re-apply" do
    around do |example|
      example.run
    ensure
      described_class.new.migrate(:up) if any_dropped_column_present?
    end

    it "restores the seven columns on `down` and removes them again on `up`" do
      described_class.new.migrate(:down)
      DROPPED_COLUMNS.each do |name|
        expect(column_for(name)).not_to be_nil, "expected #{name} restored on down"
      end

      described_class.new.migrate(:up)
      DROPPED_COLUMNS.each do |name|
        expect(column_for(name)).to be_nil, "expected #{name} dropped again on up"
      end
    end

    it "recreates the boolean columns with their original NOT NULL / default options on `down`" do
      described_class.new.migrate(:down)
      %w[slack_enabled discord_enabled].each do |name|
        col = column_for(name)
        expect(col.sql_type).to eq("boolean")
        expect(col.null).to be(false)
        expect(col.default).to be(false)
      end
    ensure
      described_class.new.migrate(:up) if any_dropped_column_present?
    end
  end
end
