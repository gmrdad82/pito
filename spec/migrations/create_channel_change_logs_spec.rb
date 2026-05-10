require "rails_helper"
require Rails.root.join(
  "db/migrate/20260510210001_create_channel_change_logs.rb"
)

# Phase 7.5 §11a — channel_change_logs table migration.
RSpec.describe CreateChannelChangeLogs, type: :model do
  EXPECTED_LOG_COLUMNS = {
    "id"                  => :integer,
    "channel_id"          => :integer,
    "field"               => :string,
    "old_value"           => :string,
    "new_value"           => :string,
    "changed_at"          => :datetime,
    "changed_by_user_id"  => :integer,
    "created_at"          => :datetime,
    "updated_at"          => :datetime
  }.freeze

  def table_exists?
    ActiveRecord::Base.connection.table_exists?(:channel_change_logs)
  end

  def column_for(name)
    return nil unless table_exists?

    ActiveRecord::Base.connection.columns(:channel_change_logs)
      .find { |c| c.name == name }
  end

  describe "post-migration state" do
    it "creates the channel_change_logs table" do
      expect(table_exists?).to be(true)
    end

    it "carries every expected column" do
      EXPECTED_LOG_COLUMNS.each_key do |name|
        expect(column_for(name)).not_to be_nil
      end
    end

    it "marks NOT NULL on channel_id / field / new_value / changed_at / changed_by_user_id" do
      %w[channel_id field new_value changed_at changed_by_user_id].each do |name|
        col = column_for(name)
        expect(col).not_to be_nil
        expect(col.null).to be(false), "expected #{name} to be NOT NULL"
      end
    end

    it "permits NULL on old_value" do
      expect(column_for("old_value").null).to be(true)
    end

    it "indexes channel_id / changed_at / changed_by_user_id" do
      indexes = ActiveRecord::Base.connection.indexes(:channel_change_logs)
      names = indexes.map(&:name)
      expect(names).to include("index_channel_change_logs_on_channel_id")
      expect(names).to include("index_channel_change_logs_on_changed_at")
      expect(names).to include("index_channel_change_logs_on_changed_by_user_id")
    end

    it "wires the FK to channels with ON DELETE CASCADE" do
      fk = ActiveRecord::Base.connection
        .foreign_keys(:channel_change_logs)
        .find { |f| f.column == "channel_id" }
      expect(fk).not_to be_nil
      expect(fk.options[:on_delete]).to eq(:cascade)
    end

    it "wires the FK to users with ON DELETE RESTRICT" do
      fk = ActiveRecord::Base.connection
        .foreign_keys(:channel_change_logs)
        .find { |f| f.column == "changed_by_user_id" }
      expect(fk).not_to be_nil
      expect(fk.options[:on_delete]).to eq(:restrict)
    end
  end

  describe "rollback + re-apply" do
    around do |example|
      example.run
    ensure
      unless table_exists?
        described_class.new.migrate(:up)
      end
    end

    it "drops the table on `down` and recreates it on `up`" do
      described_class.new.migrate(:down)
      expect(table_exists?).to be(false)

      described_class.new.migrate(:up)
      expect(table_exists?).to be(true)
      EXPECTED_LOG_COLUMNS.each_key do |name|
        expect(column_for(name)).not_to be_nil
      end
    end
  end
end
