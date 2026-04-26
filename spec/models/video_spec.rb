require "rails_helper"

RSpec.describe Video, type: :model do
  subject { build(:video) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to have_many(:video_stats).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:youtube_video_id) }
    it { is_expected.to validate_uniqueness_of(:youtube_video_id).case_insensitive }
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:privacy_status).with_values(public_video: 0, unlisted: 1, private_video: 2) }
  end

  describe "new fields" do
    it "supports scheduled_publish_at" do
      video = build(:video, :scheduled)
      expect(video.scheduled_publish_at).to be_future
      expect(video.private_video?).to be true
    end

    it "defaults made_for_kids to false" do
      video = build(:video)
      expect(video.made_for_kids).to be false
    end

    it "stores category_id and default_language" do
      video = create(:video, category_id: 22, default_language: "pt")
      video.reload
      expect(video.category_id).to eq(22)
      expect(video.default_language).to eq("pt")
    end
  end
end
