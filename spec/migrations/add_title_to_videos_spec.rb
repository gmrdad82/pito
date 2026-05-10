require "rails_helper"
require Rails.root.join(
  "db/migrate/20260510210002_add_title_to_videos.rb"
)

# Phase 7.5 §11a — `add_title_to_videos` no-op.
#
# At dispatch time, `videos.title` was already present on schema
# (added by Phase 12's `expand_videos_for_data_api_v3`). 11a's spec
# stipulates the migration becomes a no-op and the agent reports.
# These specs lock that posture so a future regression to a `change`
# body that actually mutates the column fails loudly.
RSpec.describe AddTitleToVideos, type: :model do
  def title_column
    ActiveRecord::Base.connection.columns(:videos).find { |c| c.name == "title" }
  end

  describe "post-migration state" do
    it "leaves the pre-existing videos.title column intact" do
      col = title_column
      expect(col).not_to be_nil
      expect(col.sql_type).to start_with("character varying")
    end

    it "is a structural no-op (running up + down is safe)" do
      expect { described_class.new.migrate(:down) }.not_to raise_error
      expect { described_class.new.migrate(:up) }.not_to raise_error
      expect(title_column).not_to be_nil
    end
  end
end
