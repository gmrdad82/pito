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

      it "sets unlocked_at to Time.current on the highest newly-unlocked tier" do
        freeze_time do
          results = described_class.call(achievable: video, metric: "views", value: 10)
          highest = results.max_by(&:threshold)
          expect(highest.unlocked_at).to eq(Time.current)
        end
      end
    end

    # ── staggered unlock timestamps ────────────────────────────────────────────

    context "staggering unlocked_at across multiple newly-unlocked tiers" do
      it "spaces timestamps 1 second apart, ending at Time.current for the highest tier" do
        freeze_time do
          # value 25 → thresholds 1, 2, 5, 10, 20 (K = 5); next in series is 50
          results      = described_class.call(achievable: video, metric: "views", value: 25)
          ascending    = [ 1, 2, 5, 10, 20 ]
          by_threshold = results.index_by(&:threshold)
          k            = ascending.length

          ascending.each_with_index do |threshold, index|
            expected = Time.current - (k - 1 - index).seconds
            expect(by_threshold[threshold].unlocked_at).to eq(expected)
          end

          expect(by_threshold[20].unlocked_at).to eq(Time.current)
          expect(by_threshold[1].unlocked_at).to eq(Time.current - (k - 1).seconds)
        end
      end

      it "keeps each adjacent tier exactly 1 second apart" do
        freeze_time do
          results = described_class.call(achievable: video, metric: "views", value: 25)
          diffs   = results.sort_by(&:threshold).map(&:unlocked_at).each_cons(2).map { |a, b| b - a }
          expect(diffs).to all(eq(1.second))
        end
      end

      it "sets created_at equal to unlocked_at on every staggered row" do
        freeze_time do
          results = described_class.call(achievable: video, metric: "views", value: 25)
          results.each { |record| expect(record.created_at).to eq(record.unlocked_at) }
        end
      end

      it "orders ascending by unlocked_at from the lowest tier (oldest) to the highest (newest)" do
        freeze_time do
          described_class.call(achievable: video, metric: "views", value: 25)
          ordered = Achievement.where(achievable: video, metric: "views").order(:unlocked_at)
          expect(ordered.map(&:threshold)).to eq([ 1, 2, 5, 10, 20 ])
        end
      end
    end

    context "when value crosses exactly one new threshold" do
      it "sets unlocked_at to Time.current with no stagger offset" do
        freeze_time do
          results = described_class.call(achievable: video, metric: "views", value: 1)
          expect(results.map(&:threshold)).to eq([ 1 ])
          expect(results.first.unlocked_at).to eq(Time.current)
        end
      end
    end

    context "when some thresholds are already unlocked with an older timestamp" do
      it "staggers only the newly-inserted tiers while preserving pre-existing unlocked_at" do
        old_time = 3.days.ago

        create(:achievement, achievable: video, metric: "views", threshold: 1, unlocked_at: old_time)
        create(:achievement, achievable: video, metric: "views", threshold: 2, unlocked_at: old_time)
        create(:achievement, achievable: video, metric: "views", threshold: 5, unlocked_at: old_time)

        freeze_time do
          results = described_class.call(achievable: video, metric: "views", value: 25)

          # 1, 2, 5 already unlocked → only 10, 20 are newly inserted this call
          expect(results.map(&:threshold)).to contain_exactly(10, 20)

          by_threshold = results.index_by(&:threshold)
          expect(by_threshold[20].unlocked_at).to eq(Time.current)
          expect(by_threshold[10].unlocked_at).to eq(Time.current - 1.second)

          [ 1, 2, 5 ].each do |threshold|
            preexisting = Achievement.find_by(achievable: video, metric: "views", threshold: threshold)
            expect(preexisting.unlocked_at).to be_within(1.second).of(old_time)
          end
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
