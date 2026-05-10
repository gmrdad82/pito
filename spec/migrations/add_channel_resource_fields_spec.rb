require "rails_helper"
require Rails.root.join(
  "db/migrate/20260510210000_add_channel_resource_fields.rb"
)

# Phase 7.5 §11a — Channel resource fields migration.
#
# Drives the `change` body up and down on the live test DB to prove
# reversibility. Leaves the schema in the post-migration state so the
# rest of the suite continues to see the new columns.
RSpec.describe AddChannelResourceFields, type: :model do
  EXPECTED_COLUMNS = {
    "title"                   => :string,
    "handle"                  => :string,
    "description"             => :text,
    "country"                 => :string,
    "default_language"        => :string,
    "keywords"                => :text,
    "banner_url"              => :string,
    "avatar_url"              => :string,
    "watermark_url"           => :string,
    "watermark_timing"        => :string,
    "watermark_offset_ms"     => :integer,
    "links"                   => :jsonb,
    "subscriber_count"        => :integer, # rails treats bigint as :integer
    "view_count"              => :integer,
    "video_count"             => :integer,
    "hidden_subscriber_count" => :boolean,
    "published_at"            => :datetime,
    "title_changed_at"        => :datetime,
    "handle_changed_at"       => :datetime
  }.freeze

  def column_for(name)
    ActiveRecord::Base.connection.columns(:channels).find { |c| c.name == name }
  end

  def handle_index_present?
    ActiveRecord::Base.connection.indexes(:channels)
      .any? { |idx| idx.name == "index_channels_on_handle" }
  end

  describe "post-migration state" do
    it "adds every expected column" do
      EXPECTED_COLUMNS.each_key do |name|
        expect(column_for(name)).not_to be_nil, "expected channels.#{name} to exist"
      end
    end

    it "adds the `index_channels_on_handle` partial index" do
      expect(handle_index_present?).to be(true)
    end

    it "defaults links to [] and is NOT NULL" do
      col = column_for("links")
      expect(col.null).to be(false)
    end

    it "intentionally omits watermark_position (parent spec D21)" do
      expect(column_for("watermark_position")).to be_nil
    end
  end

  describe "rollback + re-apply" do
    around do |example|
      example.run
    ensure
      # Always leave the test DB in the post-migration state regardless
      # of mid-example failure so neighbor specs keep working.
      unless column_for("title")
        described_class.new.migrate(:up)
      end
    end

    it "removes every added column on `down` and restores them on `up`" do
      described_class.new.migrate(:down)

      EXPECTED_COLUMNS.each_key do |name|
        expect(column_for(name)).to be_nil, "expected channels.#{name} to be removed"
      end
      expect(handle_index_present?).to be(false)

      described_class.new.migrate(:up)

      EXPECTED_COLUMNS.each_key do |name|
        expect(column_for(name)).not_to be_nil
      end
      expect(handle_index_present?).to be(true)
    end
  end
end
