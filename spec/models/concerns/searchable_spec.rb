require "rails_helper"

RSpec.describe Searchable do
  describe "Video searchable configuration" do
    it "defines searchable fields" do
      expect(Video.searchable_fields).to eq([ :title, :description, :tags, :category_id, :default_language ])
    end

    it "defines filterable fields" do
      expect(Video.filterable_fields).to eq([ :channel_id, :privacy_status ])
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

  describe "Video after_commit callbacks" do
    it "enqueues SearchIndexJob on create" do
      expect {
        create(:video)
      }.to have_enqueued_job(SearchIndexJob)
    end

    it "enqueues SearchIndexJob on update" do
      video = create(:video)
      expect {
        video.update!(title: "new title")
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
