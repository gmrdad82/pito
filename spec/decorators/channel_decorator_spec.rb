require "rails_helper"

RSpec.describe ChannelDecorator do
  let(:channel) { create(:channel, subscriber_count: 12_500, view_count: 1_000_000) }
  let(:decorator) { described_class.new(channel) }

  describe "#formatted_subscriber_count" do
    it "formats with delimiter" do
      expect(decorator.formatted_subscriber_count).to eq("12,500")
    end
  end

  describe "#formatted_view_count" do
    it "formats with delimiter" do
      expect(decorator.formatted_view_count).to eq("1,000,000")
    end
  end

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "includes expected keys" do
      expect(json).to include(:id, :youtube_channel_id, :title, :connected, :subscriber_count, :view_count)
    end
  end

  describe "#as_detail_json" do
    before { create(:video, channel: channel) }

    let(:json) { decorator.as_detail_json }

    it "includes detail fields" do
      expect(json).to include(:description, :thumbnail_url, :videos)
    end

    it "includes nested videos" do
      expect(json[:videos]).to be_an(Array)
      expect(json[:videos].first).to include(:id, :title)
    end
  end
end
