# frozen_string_literal: true

require "rails_helper"

RSpec.describe AchievementMetric do
  it "has a working factory" do
    expect(build(:achievement_metric)).to be_valid
  end

  describe "validations" do
    it "requires metric" do
      expect(build(:achievement_metric, metric: nil)).not_to be_valid
    end

    it "rejects a metric outside Achievement::METRICS" do
      expect(build(:achievement_metric, metric: "revenue")).not_to be_valid
    end

    it "accepts each allowed metric" do
      Achievement::METRICS.each do |metric|
        expect(build(:achievement_metric, metric: metric)).to be_valid
      end
    end

    it "requires value" do
      expect(build(:achievement_metric, value: nil)).not_to be_valid
    end

    it "rejects a negative value" do
      expect(build(:achievement_metric, value: -1)).not_to be_valid
    end

    it "accepts zero value" do
      expect(build(:achievement_metric, value: 0)).to be_valid
    end

    describe "uniqueness of metric scoped to (achievable)" do
      let(:video) { create(:video) }

      before { create(:achievement_metric, achievable: video, metric: "views") }

      it "is invalid when the same (achievable, metric) already exists" do
        dup = build(:achievement_metric, achievable: video, metric: "views")
        expect(dup).not_to be_valid
        expect(dup.errors[:metric]).to be_present
      end

      it "allows a different metric for the same achievable" do
        expect(build(:achievement_metric, achievable: video, metric: "likes")).to be_valid
      end

      it "raises on DB-level duplicate insert" do
        dup = build(:achievement_metric, achievable: video, metric: "views")
        dup.valid? # bypass model validation to attempt DB insert
        expect { dup.save(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  describe "polymorphic achievable association" do
    it "links to a channel" do
      channel = create(:channel)
      am = create(:achievement_metric, achievable: channel)
      expect(am.achievable).to eq(channel)
      expect(am.achievable_type).to eq("Channel")
    end

    it "links to a video" do
      video = create(:video)
      am = create(:achievement_metric, achievable: video)
      expect(am.achievable).to eq(video)
      expect(am.achievable_type).to eq("Video")
    end

    it "links to a game" do
      game = create(:game)
      am = create(:achievement_metric, achievable: game, metric: "views")
      expect(am.achievable).to eq(game)
      expect(am.achievable_type).to eq("Game")
    end

    it "is destroyed with the achievable" do
      video = create(:video)
      create(:achievement_metric, achievable: video)
      expect { video.destroy }.to change(AchievementMetric, :count).by(-1)
    end
  end
end
