require "rails_helper"

# Phase 13.2 — Analytics sync engine. Boundary tests encode the
# master-agent decision (open question 6): "uploaded in last 90 days"
# is INCLUSIVE of day 90; "> 100 views" is STRICT.
RSpec.describe Youtube::ActiveVideoClassifier do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, youtube_connection: connection) }

  describe ".active?" do
    it "is true for a video published within 90 days" do
      video = create(:video, channel: channel, published_at: 60.days.ago)
      expect(described_class.active?(video)).to be true
    end

    it "is false for a video published > 90 days ago and no recent views" do
      video = create(:video, channel: channel, published_at: 100.days.ago)
      expect(described_class.active?(video)).to be false
    end

    it "is true for a video with > 100 views in the last 7 days regardless of age" do
      video = create(:video, channel: channel, published_at: 1.year.ago)
      create(:video_daily, video: video, date: 2.days.ago.to_date, views: 150)
      expect(described_class.active?(video)).to be true
    end

    it "is false at the boundary — exactly 100 views in 7 days (> 100 strict)" do
      video = create(:video, channel: channel, published_at: 1.year.ago)
      create(:video_daily, video: video, date: 2.days.ago.to_date, views: 100)
      expect(described_class.active?(video)).to be false
    end

    it "is true at the boundary — exactly 90 days old (>= 90.days.ago inclusive)" do
      video = create(:video, channel: channel, published_at: 90.days.ago + 1.minute)
      expect(described_class.active?(video)).to be true
    end
  end

  describe ".active_for(connection)" do
    let!(:in_window_video) do
      v = create(:video, channel: channel, published_at: 30.days.ago)
      v
    end

    let!(:out_of_window_video) do
      create(:video, channel: channel, published_at: 200.days.ago)
    end

    let(:other_connection) { create(:youtube_connection, user: user, google_subject_id: "other-subject-99") }
    let(:other_channel)    { create(:channel, youtube_connection: other_connection) }
    let!(:other_video)     { create(:video, channel: other_channel, published_at: 30.days.ago) }

    it "returns videos belonging to the connection's channels" do
      ids = described_class.active_for(connection).pluck(:id)
      expect(ids).to include(in_window_video.id)
    end

    it "excludes videos under other connections" do
      ids = described_class.active_for(connection).pluck(:id)
      expect(ids).not_to include(other_video.id)
    end

    it "does not return inactive videos" do
      ids = described_class.active_for(connection).pluck(:id)
      expect(ids).not_to include(out_of_window_video.id)
    end
  end
end
