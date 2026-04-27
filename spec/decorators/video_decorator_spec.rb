require "rails_helper"

RSpec.describe VideoDecorator do
  let(:channel) { create(:channel, title: "test channel") }
  let(:video) { create(:video, channel: channel, duration_seconds: 3661, privacy_status: :public_video, published_at: 2.days.ago) }
  let(:decorator) { described_class.new(video) }

  describe "#formatted_duration" do
    it "returns formatted time" do
      expect(decorator.formatted_duration).to eq("1:01:01")
    end
  end

  describe "#formatted_privacy" do
    it "strips _video suffix" do
      expect(decorator.formatted_privacy).to eq("public")
    end
  end

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "includes expected keys" do
      expect(json).to include(:id, :youtube_video_id, :title, :channel_id, :channel_title, :privacy_status, :published_at)
    end

    it "includes channel title" do
      expect(json[:channel_title]).to eq("test channel")
    end
  end

  describe "#as_detail_json" do
    before { create(:video_stat, video: video, date: Date.current, views: 100) }

    let(:json) { decorator.as_detail_json }

    it "includes detail fields" do
      expect(json).to include(:description, :thumbnail_url, :tags, :stats)
    end

    it "includes stats array" do
      expect(json[:stats]).to be_an(Array)
      expect(json[:stats].first).to include(:date, :views)
    end
  end
end
