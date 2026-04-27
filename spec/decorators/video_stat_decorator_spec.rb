require "rails_helper"

RSpec.describe VideoStatDecorator do
  let(:video) { create(:video) }
  let(:stat) { create(:video_stat, video: video, date: Date.new(2026, 4, 27), views: 500, likes: 25, comments: 3, shares: 5, watch_time_minutes: 120) }
  let(:decorator) { described_class.new(stat) }

  describe "#as_json_entry" do
    let(:json) { decorator.as_json_entry }

    it "includes all stat fields" do
      expect(json).to eq(
        date: "2026-04-27",
        views: 500,
        likes: 25,
        comments: 3,
        shares: 5,
        watch_time_minutes: 120
      )
    end
  end
end
