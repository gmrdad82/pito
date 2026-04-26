require "rails_helper"

RSpec.describe Video, type: :model do
  subject { build(:video) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to have_many(:video_stats).dependent(:destroy) }
    it { is_expected.to have_one(:production).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:youtube_video_id) }
    it { is_expected.to validate_uniqueness_of(:youtube_video_id).case_insensitive }
    it { is_expected.to validate_presence_of(:title) }
  end
end
