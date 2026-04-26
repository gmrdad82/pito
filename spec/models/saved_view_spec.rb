require "rails_helper"

RSpec.describe SavedView, type: :model do
  subject { build(:saved_view) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:kind) }
    it { is_expected.to validate_presence_of(:url) }
    it { is_expected.to validate_uniqueness_of(:url).scoped_to(:kind).case_insensitive }
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:kind).with_values(channels: 0, videos: 1) }
  end

  describe "#display_name" do
    it "returns kind and name" do
      view = build(:saved_view, kind: :channels, name: "My Favorites")
      expect(view.display_name).to eq("Channels: My Favorites")
    end
  end
end
