require "rails_helper"

# Phase 11 §01a — Video edit page polish. End-screen model spec.
RSpec.describe VideoEndScreen, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "enum kind" do
    it "maps the four kinds" do
      expect(described_class.kinds).to eq(
        "related_video" => 0,
        "related_channel" => 1,
        "related_playlist" => 2,
        "none" => 3
      )
    end

    it "exposes prefixed predicates" do
      es = build(:video_end_screen, kind: :related_video)
      expect(es.kind_related_video?).to be(true)
      expect(es.kind_none?).to be(false)
    end
  end

  describe "validations" do
    subject { build(:video_end_screen) }

    it { is_expected.to validate_presence_of(:kind) }
    it { is_expected.to validate_length_of(:target_label).is_at_most(100) }

    it "requires target_id for related_video" do
      es = build(:video_end_screen, kind: :related_video, target_id: nil)
      expect(es).not_to be_valid
      expect(es.errors[:target_id]).to be_present
    end

    it "requires target_id for related_channel" do
      es = build(:video_end_screen, kind: :related_channel, target_id: "")
      expect(es).not_to be_valid
    end

    it "allows blank target_id for kind: none" do
      video = create(:video)
      es = build(:video_end_screen, :none, video: video)
      expect(es).to be_valid
    end

    it "forbids mixing a none row with other rows" do
      video = create(:video)
      create(:video_end_screen, video: video, kind: :related_video)
      none = build(:video_end_screen, :none, video: video)
      expect(none).not_to be_valid
      expect(none.errors[:base]).to include(/cannot mix/)
    end

    it "rejects a 5th non-none row" do
      video = create(:video)
      4.times do |i|
        create(:video_end_screen,
               video: video,
               kind: :related_video,
               target_id: "yt#{i}",
               position: i)
      end
      fifth = build(:video_end_screen,
                    video: video,
                    kind: :related_video,
                    target_id: "yt5",
                    position: 5)
      expect(fifth).not_to be_valid
      expect(fifth.errors[:base]).to include(/no more than 4/)
    end

    it "allows 4 non-none rows" do
      video = create(:video)
      4.times do |i|
        rec = build(:video_end_screen,
                    video: video,
                    kind: :related_video,
                    target_id: "yt#{i}",
                    position: i)
        expect(rec).to be_valid
        rec.save!
      end
    end
  end

  describe ".ordered scope" do
    it "orders by position ASC" do
      video = create(:video)
      e2 = create(:video_end_screen, video: video, position: 2, target_id: "b")
      e1 = create(:video_end_screen, video: video, position: 1, target_id: "a")
      expect(video.video_end_screens.ordered).to eq([ e1, e2 ])
    end
  end
end
