require "rails_helper"

RSpec.describe Analytics::ChannelDecorator do
  let(:channel) { create(:channel) }
  let(:decorator) { described_class.new(channel) }

  describe "#window_summary" do
    it "returns the matching ChannelWindowSummary row" do
      summary = create(:channel_window_summary, channel: channel, window: "28d")
      expect(decorator.window_summary("28d")).to eq(summary)
    end

    it "returns nil for an unsynced window" do
      expect(decorator.window_summary("90d")).to be_nil
    end
  end

  describe "#daily_for_window" do
    it "returns ChannelDaily rows in the window's date range, ordered by date" do
      old_row = create(:channel_daily, channel: channel, date: 30.days.ago.to_date)
      mid_row = create(:channel_daily, channel: channel, date: 5.days.ago.to_date)
      _other_channel_row = create(:channel_daily, date: 5.days.ago.to_date)

      result = decorator.daily_for_window(7.days.ago.to_date, Date.current).to_a
      expect(result).to eq([ mid_row ])
      expect(result).not_to include(old_row)
    end
  end

  describe "#top_videos" do
    it "returns the channel's top_videos_window rows for the given window, ordered by rank" do
      video1 = create(:video, channel: channel)
      video2 = create(:video, channel: channel)
      r2 = create(:top_videos_window, host_channel: channel, video: video2, window: "28d", rank: 2)
      r1 = create(:top_videos_window, host_channel: channel, video: video1, window: "28d", rank: 1)
      _other_window = create(:top_videos_window, host_channel: channel, video: video1, window: "7d", rank: 1)

      expect(decorator.top_videos("28d").to_a).to eq([ r1, r2 ])
    end
  end

  describe "#geography_summed" do
    it "returns SUM-aggregated views per country across the channel's videos" do
      video1 = create(:video, channel: channel)
      video2 = create(:video, channel: channel)
      create(:video_daily_by_country, video: video1, country_code: "US", date: 1.day.ago.to_date, views: 100)
      create(:video_daily_by_country, video: video2, country_code: "US", date: 1.day.ago.to_date, views: 50)
      create(:video_daily_by_country, video: video1, country_code: "GB", date: 1.day.ago.to_date, views: 30)

      result = decorator.geography_summed(7.days.ago.to_date, Date.current)
      expect(result["US"]).to eq(150)
      expect(result["GB"]).to eq(30)
    end
  end

  describe "#demographics_summed" do
    it "returns SUM-aggregated viewer_percentage per (age_group, gender)" do
      video = create(:video, channel: channel)
      create(:video_daily_by_age_group_gender,
             video: video,
             age_group: "AGE_18_24",
             gender: "MALE",
             date: 1.day.ago.to_date,
             viewer_percentage: 0.4)
      create(:video_daily_by_age_group_gender,
             video: video,
             age_group: "AGE_18_24",
             gender: "FEMALE",
             date: 1.day.ago.to_date,
             viewer_percentage: 0.3)

      result = decorator.demographics_summed(7.days.ago.to_date, Date.current)
      expect(result[[ "AGE_18_24", "MALE" ]]).to eq(0.4)
      expect(result[[ "AGE_18_24", "FEMALE" ]]).to eq(0.3)
    end
  end
end
