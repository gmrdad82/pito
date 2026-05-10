require "rails_helper"

# Phase 12 — Video re-declares searchable / filterable fields now
# that the writable subset (title, description, tags, privacy_status,
# category_id) is back. Meilisearch indexing is still a follow-up; the
# concern stays declarative.
RSpec.describe Searchable do
  describe "Video searchable configuration" do
    it "declares title and description as searchable" do
      expect(Video.searchable_fields).to eq([ :title, :description ])
    end

    it "declares filterable fields for the new metadata columns" do
      expect(Video.filterable_fields).to include(:privacy_status, :category_id, :channel_id, :project_id)
    end
  end

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

  describe "Video after_commit callbacks (Searchable concern stays included)" do
    it "enqueues SearchIndexJob on create" do
      expect {
        create(:video)
      }.to have_enqueued_job(SearchIndexJob)
    end

    it "enqueues SearchIndexJob on update" do
      video = create(:video)
      expect {
        video.update!(star: true)
      }.to have_enqueued_job(SearchIndexJob)
    end

    it "enqueues SearchRemoveJob on destroy" do
      video = create(:video)
      expect {
        video.destroy!
      }.to have_enqueued_job(SearchRemoveJob)
    end
  end
end
