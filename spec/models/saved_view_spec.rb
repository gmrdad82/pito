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

  describe ".ordered" do
    it "orders by position asc then created_at desc" do
      v2 = create(:saved_view, position: 1)
      v1 = create(:saved_view, position: 0)
      v3 = create(:saved_view, position: 1, created_at: 1.day.ago)
      expect(SavedView.ordered).to eq([ v1, v2, v3 ])
    end
  end

  describe "#entity_labels" do
    it "returns channel id strings as labels for existing channels" do
      channel = create(:channel)
      view = build(:saved_view, kind: :channels, url: "/channels/panes?ids=#{channel.id}")
      labels = view.entity_labels
      expect(labels.size).to eq(1)
      expect(labels.first[:title]).to eq(channel.id.to_s)
      expect(labels.first[:deleted]).to be false
    end

    it "marks deleted entities" do
      view = build(:saved_view, kind: :channels, url: "/channels/panes?ids=99999")
      labels = view.entity_labels
      expect(labels.first[:title]).to eq("[deleted]")
      expect(labels.first[:deleted]).to be true
    end

    it "handles single entity URLs (channels)" do
      channel = create(:channel)
      view = build(:saved_view, kind: :channels, url: "/channels/#{channel.id}")
      expect(view.entity_labels.size).to eq(1)
      expect(view.entity_labels.first[:title]).to eq(channel.id.to_s)
    end

    it "handles video kind (still uses title)" do
      video = create(:video)
      view = build(:saved_view, kind: :videos, url: "/videos/panes?ids=#{video.id}")
      expect(view.entity_labels.first[:title]).to eq(video.title)
    end

    it "returns empty for URLs without IDs" do
      view = build(:saved_view, kind: :channels, url: "/channels")
      expect(view.entity_labels).to eq([])
    end
  end

  describe "#display_name_with_deletions" do
    it "joins channel ids with +" do
      c1 = create(:channel)
      c2 = create(:channel)
      view = build(:saved_view, kind: :channels, url: "/channels/panes?ids=#{c1.id},#{c2.id}", name: "test")
      expect(view.display_name_with_deletions).to eq("#{c1.id} + #{c2.id}")
    end

    it "shows [deleted] for missing channels" do
      channel = create(:channel)
      view = build(:saved_view, kind: :channels, url: "/channels/panes?ids=#{channel.id},99999", name: "test")
      expect(view.display_name_with_deletions).to eq("#{channel.id} + [deleted]")
    end

    it "falls back to name when no IDs in URL" do
      view = build(:saved_view, kind: :channels, url: "/channels", name: "all channels")
      expect(view.display_name_with_deletions).to eq("all channels")
    end
  end
end
