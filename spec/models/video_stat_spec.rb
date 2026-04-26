require "rails_helper"

RSpec.describe VideoStat, type: :model do
  subject { build(:video_stat) }

  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_uniqueness_of(:date).scoped_to(:video_id) }
  end
end
