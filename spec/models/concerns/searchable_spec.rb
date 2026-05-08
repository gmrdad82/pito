require "rails_helper"

# Phase 7 Path A2 (literal full retract). Video declares no
# `searchable :*` / `filterable :*` lines; the index/remove hooks
# still fire (the Searchable concern is still included), but the
# index document only has `id` and queries return zero matches.
RSpec.describe Searchable do
  describe "Video searchable configuration" do
    it "defines an empty searchable_fields array" do
      expect(Video.searchable_fields).to eq([])
    end

    it "defines an empty filterable_fields array" do
      expect(Video.filterable_fields).to eq([])
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
