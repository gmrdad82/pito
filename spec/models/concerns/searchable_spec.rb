require "rails_helper"

# Phase 34 (2026-05-18) — Video no longer joins the Meilisearch
# corpus. The unified `/games` index covers Game + Bundle only; the
# previous `videos_<env>` index is left to drift stale (no writes,
# no destroy hooks). Video does NOT include Searchable anymore.
#
# Channel was removed from the Searchable surface earlier (Phase A → B);
# the assertions below pin that down so a future "let's index channels
# again" change has to update this spec deliberately.
RSpec.describe Searchable do
  describe "Channel does not include Searchable (Phase A → B removed it)" do
    it "does not respond to .searchable_fields" do
      expect(Channel).not_to respond_to(:searchable_fields)
    end

    it "does not enqueue SearchIndexJob on create" do
      expect {
        create(:channel)
      }.not_to have_enqueued_job(SearchIndexJob)
    end
  end

  describe "Video does not include Searchable (Phase 34 removed it)" do
    it "does not respond to .searchable_fields" do
      expect(Video).not_to respond_to(:searchable_fields)
    end

    it "does not enqueue SearchIndexJob on create" do
      expect {
        create(:video)
      }.not_to have_enqueued_job(SearchIndexJob)
    end

    it "does not enqueue SearchRemoveJob on destroy" do
      video = create(:video)
      expect {
        video.destroy!
      }.not_to have_enqueued_job(SearchRemoveJob)
    end
  end
end
