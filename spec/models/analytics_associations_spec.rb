require "rails_helper"

# Phase 13.1 — sanity check that Channel and Video declare every
# has_many for the analytics tables with `dependent: :delete_all`.
RSpec.describe "analytics associations on Channel / Video", type: :model do
  describe Channel do
    it "has_many :channel_dailies with delete_all" do
      assoc = Channel.reflect_on_association(:channel_dailies)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :channel_window_summaries with delete_all" do
      assoc = Channel.reflect_on_association(:channel_window_summaries)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :top_videos_windows with delete_all" do
      assoc = Channel.reflect_on_association(:top_videos_windows)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "cascades channel_dailies on Channel#destroy" do
      channel = create(:channel)
      create(:channel_daily, channel: channel)
      expect { channel.destroy }.to change(ChannelDaily, :count).by(-1)
    end
  end

  describe Video do
    it "has_many :video_dailies with delete_all" do
      assoc = Video.reflect_on_association(:video_dailies)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_daily_by_countries with delete_all" do
      assoc = Video.reflect_on_association(:video_daily_by_countries)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_daily_by_device_types with delete_all" do
      assoc = Video.reflect_on_association(:video_daily_by_device_types)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_daily_by_operating_systems with delete_all" do
      assoc = Video.reflect_on_association(:video_daily_by_operating_systems)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_daily_by_traffic_sources with delete_all" do
      assoc = Video.reflect_on_association(:video_daily_by_traffic_sources)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_daily_by_subscribed_statuses with delete_all" do
      assoc = Video.reflect_on_association(:video_daily_by_subscribed_statuses)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_daily_by_age_group_genders with delete_all" do
      assoc = Video.reflect_on_association(:video_daily_by_age_group_genders)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_window_summaries with delete_all" do
      assoc = Video.reflect_on_association(:video_window_summaries)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end

    it "has_many :video_retentions with delete_all" do
      assoc = Video.reflect_on_association(:video_retentions)
      expect(assoc).to be_present
      expect(assoc.options[:dependent]).to eq(:delete_all)
    end
  end
end
