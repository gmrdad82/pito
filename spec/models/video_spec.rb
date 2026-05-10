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
  end

  describe "Phase 9 — surviving columns" do
    it "stores star + last_synced_at + youtube_connection_id" do
      connection = create(:youtube_connection)
      video = create(:video, star: true, last_synced_at: Time.current, youtube_connection: connection)
      video.reload
      expect(video.star?).to be(true)
      expect(video.last_synced_at).to be_within(1.second).of(Time.current)
      expect(video.youtube_connection).to eq(connection)
    end

    it ".starred returns only starred videos" do
      starred = create(:video, :starred)
      _other  = create(:video)
      expect(Video.starred).to eq([ starred ])
    end
  end
end
