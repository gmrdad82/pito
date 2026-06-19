# frozen_string_literal: true

require "rails_helper"

# YouTube's videos.update rejects a `publishAt` that isn't RFC3339 in UTC
# ("invalidPublishAt"). `build_status_object` must coerce a local Time to a
# `...Z` RFC3339 string while passing already-formatted strings (and nil)
# through untouched.
RSpec.describe Channel::Youtube::VideosClient, type: :service do
  describe "#build_status_object — publish_at RFC3339 serialization" do
    let(:connection) { create(:youtube_connection) }

    subject(:client) { described_class.new(connection) }

    def status_for(publish_at)
      client.send(:build_status_object, { privacy_status: "private", publish_at: publish_at })
    end

    it "serializes a local Time as a UTC RFC3339 `Z` string (not `+0200`)" do
      local = Time.new(2026, 6, 19, 3, 10, 10, "+02:00")
      expect(status_for(local).publish_at).to eq("2026-06-19T01:10:10Z")
    end

    it "passes an already-RFC3339 String through unchanged" do
      expect(status_for("2026-06-19T01:10:10Z").publish_at).to eq("2026-06-19T01:10:10Z")
    end

    it "leaves nil as nil" do
      expect(status_for(nil).publish_at).to be_nil
    end
  end
end
