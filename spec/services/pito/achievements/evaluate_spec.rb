# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievements::Evaluate do
  include ActiveSupport::Testing::TimeHelpers

  let(:channel) { create(:channel) }
  let(:video)   { create(:video) }
  let(:game)    { create(:game) }

  # ── MATRIX / metrics_for ───────────────────────────────────────────────────

  describe "the configured metric matrix (shinies.yml)" do
    it "has entries for Channel, Video, and Game" do
      expect(Pito::Achievements::Config.ceilings.keys).to contain_exactly("Channel", "Video", "Game")
    end

    it "gives Channel subs but not subs_gained" do
      expect(Pito::Achievements::Config.metrics_for("Channel")).to include("subs")
      expect(Pito::Achievements::Config.metrics_for("Channel")).not_to include("subs_gained")
    end

    it "gives Video subs_gained but not subs" do
      expect(Pito::Achievements::Config.metrics_for("Video")).to include("subs_gained")
      expect(Pito::Achievements::Config.metrics_for("Video")).not_to include("subs")
    end

    it "gives Game subs_gained but not subs" do
      expect(Pito::Achievements::Config.metrics_for("Game")).to include("subs_gained")
      expect(Pito::Achievements::Config.metrics_for("Game")).not_to include("subs")
    end
  end

  describe ".metrics_for" do
    it "returns the Channel metric list" do
      expect(described_class.metrics_for(channel)).to eq(%w[subs views watched_hours likes comments])
    end

    it "returns the Video metric list" do
      expect(described_class.metrics_for(video)).to eq(%w[subs_gained views watched_hours likes comments])
    end

    it "returns the Game metric list" do
      expect(described_class.metrics_for(game)).to eq(%w[subs_gained views watched_hours likes comments])
    end
  end

  # ── .call — basic unlocking ────────────────────────────────────────────────

  describe ".call" do
    context "when value crosses multiple thresholds" do
      it "creates an Achievement for each threshold ≤ value" do
        # value 25 → 1, 2, 5, 10, 20 (next in series is 50)
        results = described_class.call(achievable: video, metric: "views", value: 25)
        expect(results.map(&:threshold)).to contain_exactly(1, 2, 5, 10, 20)
      end

      it "returns Achievement records with the correct metric" do
        results = described_class.call(achievable: video, metric: "views", value: 25)
        expect(results.map(&:metric).uniq).to eq([ "views" ])
      end

      it "sets unlocked_at on newly created records" do
        freeze_time do
          results = described_class.call(achievable: video, metric: "views", value: 10)
          expect(results.map(&:unlocked_at).uniq).to eq([ Time.current ])
        end
      end
    end

    context "when value is below the first threshold" do
      it "returns an empty array for value 0" do
        expect(described_class.call(achievable: video, metric: "views", value: 0)).to eq([])
      end

      it "creates no Achievement rows for value 0" do
        expect {
          described_class.call(achievable: video, metric: "views", value: 0)
        }.not_to change(Achievement, :count)
      end
    end

    context "when value exactly equals a threshold" do
      it "unlocks that threshold" do
        results = described_class.call(achievable: video, metric: "views", value: 100)
        expect(results.map(&:threshold)).to include(100)
      end
    end

    # ── idempotency ───────────────────────────────────────────────────────────

    context "idempotency" do
      it "returns an empty array on the second call with the same value" do
        described_class.call(achievable: video, metric: "views", value: 10)
        second = described_class.call(achievable: video, metric: "views", value: 10)
        expect(second).to eq([])
      end

      it "does not create duplicate Achievement rows" do
        described_class.call(achievable: video, metric: "views", value: 10)
        expect {
          described_class.call(achievable: video, metric: "views", value: 10)
        }.not_to change(Achievement, :count)
      end

      it "preserves the original unlocked_at on repeated calls" do
        original_time = nil
        travel_to(2.days.ago) do
          results       = described_class.call(achievable: video, metric: "views", value: 10)
          original_time = results.first.unlocked_at
        end

        # Second call at a later time must not overwrite unlocked_at
        described_class.call(achievable: video, metric: "views", value: 10)
        expect(Achievement.find_by(achievable: video, metric: "views", threshold: 1).unlocked_at)
          .to be_within(1.second).of(original_time)
      end
    end

    # ── progressive unlocking ─────────────────────────────────────────────────

    context "when value increases over multiple calls" do
      it "unlocks only newly-crossed thresholds on the second call" do
        described_class.call(achievable: video, metric: "views", value: 10)
        # value 50 → 1,2,5,10,20,50; 1..10 already locked → only 20 and 50 new
        second = described_class.call(achievable: video, metric: "views", value: 50)
        expect(second.map(&:threshold)).to contain_exactly(20, 50)
      end

      it "does not duplicate the already-unlocked thresholds" do
        described_class.call(achievable: video, metric: "views", value: 10)
        count_before = Achievement.where(achievable: video, metric: "views").count
        described_class.call(achievable: video, metric: "views", value: 50)
        # 4 thresholds for value=10 (1,2,5,10) + 2 new (20,50) = 6 total
        expect(Achievement.where(achievable: video, metric: "views").count)
          .to eq(count_before + 2)
      end
    end

    # ── ArgumentError on bad metric ───────────────────────────────────────────

    describe "metric validation" do
      it "raises ArgumentError for subs on a Video" do
        expect {
          described_class.call(achievable: video, metric: "subs", value: 100)
        }.to raise_error(ArgumentError, /subs.*Video/i)
      end

      it "raises ArgumentError for subs_gained on a Channel" do
        expect {
          described_class.call(achievable: channel, metric: "subs_gained", value: 100)
        }.to raise_error(ArgumentError, /subs_gained.*Channel/i)
      end

      it "raises ArgumentError for a wholly unknown metric" do
        expect {
          described_class.call(achievable: video, metric: "bogus", value: 100)
        }.to raise_error(ArgumentError)
      end

      it "raises ArgumentError for subs on a Game" do
        expect {
          described_class.call(achievable: game, metric: "subs", value: 100)
        }.to raise_error(ArgumentError, /subs.*Game/i)
      end
    end

    # ── works across Channel / Video / Game ──────────────────────────────────

    describe "polymorphic achievable support" do
      it "unlocks achievements for a Channel" do
        results = described_class.call(achievable: channel, metric: "subs", value: 5)
        expect(results.map(&:threshold)).to contain_exactly(1, 2, 5)
        expect(Achievement.where(achievable: channel, metric: "subs").count).to eq(3)
      end

      it "unlocks achievements for a Video" do
        results = described_class.call(achievable: video, metric: "views", value: 2)
        expect(results.map(&:threshold)).to contain_exactly(1, 2)
        expect(Achievement.where(achievable: video, metric: "views").count).to eq(2)
      end

      it "unlocks achievements for a Game" do
        results = described_class.call(achievable: game, metric: "subs_gained", value: 2)
        expect(results.map(&:threshold)).to contain_exactly(1, 2)
        expect(Achievement.where(achievable: game, metric: "subs_gained").count).to eq(2)
      end

      it "keeps achievements for different achievables separate" do
        described_class.call(achievable: video, metric: "views", value: 10)
        described_class.call(achievable: game, metric: "views", value: 10)

        expect(Achievement.where(achievable: video, metric: "views").count).to eq(4)
        expect(Achievement.where(achievable: game, metric: "views").count).to eq(4)
      end
    end
  end
end
