require "rails_helper"

RSpec.describe Searchable do
  describe "Channel searchable configuration" do
    it "defines searchable fields" do
      expect(Channel.searchable_fields).to eq([ :title, :description ])
    end

    it "defines filterable fields" do
      expect(Channel.filterable_fields).to eq([ :connected ])
    end
  end

  describe "Video searchable configuration" do
    it "defines searchable fields" do
      expect(Video.searchable_fields).to eq([ :title, :description, :tags, :category_id, :default_language ])
    end

    it "defines filterable fields" do
      expect(Video.filterable_fields).to eq([ :channel_id, :privacy_status ])
    end
  end

  describe "after_commit callbacks" do
    it "enqueues SearchIndexJob on create" do
      expect {
        create(:channel)
      }.to have_enqueued_job(SearchIndexJob)
    end

    it "enqueues SearchIndexJob on update" do
      channel = create(:channel)
      expect {
        channel.update!(title: "new title")
      }.to have_enqueued_job(SearchIndexJob)
    end

    it "enqueues SearchRemoveJob on destroy" do
      channel = create(:channel)
      expect {
        channel.destroy!
      }.to have_enqueued_job(SearchRemoveJob)
    end
  end
end
