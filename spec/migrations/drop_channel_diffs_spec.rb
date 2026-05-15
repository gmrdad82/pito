require "rails_helper"
require Rails.root.join(
  "db/migrate/20260514164940_drop_channel_diffs.rb"
)

# Unit A0 — channel read-only conversion.
#
# Drives the `up` / `down` body on the live test DB to prove the
# `channel_diffs` table is dropped and that the migration is reversible
# (the `down` direction faithfully re-creates the original schema).
# Leaves the schema in the post-migration (table-dropped) state so the
# rest of the suite continues to see the read-only-mirror shape.
RSpec.describe DropChannelDiffs, type: :model do
  def table_exists?
    ActiveRecord::Base.connection.table_exists?(:channel_diffs)
  end

  describe "post-migration state" do
    it "has dropped the channel_diffs table" do
      expect(table_exists?).to be(false)
    end
  end

  describe "rollback + re-apply" do
    around do |example|
      example.run
    ensure
      # Always leave the test DB in the post-migration (dropped) state
      # regardless of mid-example failure so neighbor specs keep working.
      if table_exists?
        described_class.new.migrate(:up)
      end
    end

    it "re-creates the table on `down` and drops it again on `up`" do
      described_class.new.migrate(:down)
      expect(table_exists?).to be(true)

      # The reversible `down` re-creates the original columns + indexes.
      columns = ActiveRecord::Base.connection.columns(:channel_diffs).map(&:name)
      expect(columns).to include(
        "channel_id", "detected_at", "resolved_at",
        "field_diffs", "resolution_payload", "resolved_by_user_id"
      )
      index_names = ActiveRecord::Base.connection.indexes(:channel_diffs).map(&:name)
      expect(index_names).to include("index_channel_diffs_open_per_channel")

      described_class.new.migrate(:up)
      expect(table_exists?).to be(false)
    end
  end
end
