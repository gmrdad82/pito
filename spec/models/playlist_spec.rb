require "rails_helper"

RSpec.describe Playlist, type: :model do
  subject { build(:playlist) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to have_many(:playlist_items).dependent(:destroy) }
    it { is_expected.to have_many(:videos).through(:playlist_items) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:youtube_playlist_id) }
    it { is_expected.to validate_uniqueness_of(:youtube_playlist_id).case_insensitive }
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:privacy_status).with_values(public_playlist: 0, unlisted: 1, private_playlist: 2) }
  end
end
