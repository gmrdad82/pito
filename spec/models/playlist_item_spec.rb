require "rails_helper"

RSpec.describe PlaylistItem, type: :model do
  subject { build(:playlist_item) }

  describe "associations" do
    it { is_expected.to belong_to(:playlist) }
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:youtube_playlist_item_id) }
    it { is_expected.to validate_uniqueness_of(:youtube_playlist_item_id).case_insensitive }
    it { is_expected.to validate_uniqueness_of(:video_id).scoped_to(:playlist_id) }
  end
end
