# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievement do
  it "has a working factory" do
    expect(build(:achievement)).to be_valid
  end

  describe "validations" do
    it "requires metric" do
      expect(build(:achievement, metric: nil)).not_to be_valid
    end

    it "rejects a metric outside METRICS" do
      expect(build(:achievement, metric: "revenue")).not_to be_valid
    end

    it "accepts each allowed metric" do
      Achievement::METRICS.each do |metric|
        expect(build(:achievement, metric: metric)).to be_valid
      end
    end

    it "requires threshold" do
      expect(build(:achievement, threshold: nil)).not_to be_valid
    end

    it "rejects a non-positive threshold" do
      expect(build(:achievement, threshold: 0)).not_to be_valid
      expect(build(:achievement, threshold: -1)).not_to be_valid
    end

    it "requires unlocked_at" do
      expect(build(:achievement, unlocked_at: nil)).not_to be_valid
    end

    describe "uniqueness of threshold scoped to (achievable, metric)" do
      let(:video) { create(:video) }

      before { create(:achievement, achievable: video, metric: "views", threshold: 1_000) }

      it "is invalid when the same (achievable, metric, threshold) already exists" do
        dup = build(:achievement, achievable: video, metric: "views", threshold: 1_000)
        expect(dup).not_to be_valid
        expect(dup.errors[:threshold]).to be_present
      end

      it "allows a different threshold for the same (achievable, metric)" do
        expect(build(:achievement, achievable: video, metric: "views", threshold: 10_000)).to be_valid
      end

      it "allows the same threshold for a different metric on the same achievable" do
        expect(build(:achievement, achievable: video, metric: "likes", threshold: 1_000)).to be_valid
      end

      it "raises on DB-level duplicate insert" do
        dup = build(:achievement, achievable: video, metric: "views", threshold: 1_000)
        dup.valid? # bypass model validation to attempt DB insert
        expect { dup.save(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  describe "polymorphic achievable association" do
    it "links to a channel" do
      channel = create(:channel)
      achievement = create(:achievement, achievable: channel)
      expect(achievement.achievable).to eq(channel)
      expect(achievement.achievable_type).to eq("Channel")
    end

    it "links to a video" do
      video = create(:video)
      achievement = create(:achievement, achievable: video)
      expect(achievement.achievable).to eq(video)
      expect(achievement.achievable_type).to eq("Video")
    end

    it "links to a game" do
      game = create(:game)
      achievement = create(:achievement, achievable: game, metric: "views")
      expect(achievement.achievable).to eq(game)
      expect(achievement.achievable_type).to eq("Game")
    end

    it "is destroyed with the achievable" do
      video = create(:video)
      create(:achievement, achievable: video)
      expect { video.destroy }.to change(Achievement, :count).by(-1)
    end
  end
end
