require "rails_helper"

# Phase 11 §01a — Video edit page polish. Chapter model spec.
RSpec.describe VideoChapter, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    subject { build(:video_chapter) }

    it { is_expected.to validate_presence_of(:start_seconds) }
    it { is_expected.to validate_presence_of(:label) }
    it { is_expected.to validate_length_of(:label).is_at_most(100) }

    it "rejects negative start_seconds" do
      ch = build(:video_chapter, start_seconds: -1)
      expect(ch).not_to be_valid
      expect(ch.errors[:start_seconds]).to be_present
    end

    it "rejects non-integer start_seconds" do
      ch = build(:video_chapter, start_seconds: 1.5)
      expect(ch).not_to be_valid
    end

    it "rejects duplicate (video_id, start_seconds)" do
      video = create(:video)
      create(:video_chapter, video: video, start_seconds: 60, label: "first")
      dup = build(:video_chapter, video: video, start_seconds: 60, label: "duplicate")
      expect(dup).not_to be_valid
      expect(dup.errors[:start_seconds]).to be_present
    end

    it "allows the same start_seconds on different videos" do
      v1 = create(:video)
      v2 = create(:video)
      create(:video_chapter, video: v1, start_seconds: 60)
      sibling = build(:video_chapter, video: v2, start_seconds: 60)
      expect(sibling).to be_valid
    end
  end

  describe ".ordered scope" do
    it "orders by start_seconds ASC" do
      video = create(:video)
      c2 = create(:video_chapter, video: video, start_seconds: 120, label: "setup")
      c1 = create(:video_chapter, video: video, start_seconds: 0, label: "intro")
      expect(video.video_chapters.ordered).to eq([ c1, c2 ])
    end
  end
end
