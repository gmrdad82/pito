require "rails_helper"

RSpec.describe Calendar::MilestoneEvaluator do
  let(:reader_class) do
    Class.new do
      def initialize(value)
        @value = value
      end

      def read(**_args)
        @value
      end
    end
  end

  describe "#evaluate" do
    let(:rule) do
      create(:milestone_rule, threshold: 100, direction: :cross_up,
                              metric: "subscriberCount")
    end

    it "does not fire when reader returns less than threshold" do
      expect {
        described_class.new(metric_reader: reader_class.new(50)).evaluate_all!
      }.not_to change(CalendarEntry, :count)
      expect(rule.reload.fired_at).to be_nil
    end

    it "fires when reader returns the exact threshold (boundary)" do
      rule
      expect {
        described_class.new(metric_reader: reader_class.new(100)).evaluate_all!
      }.to change(CalendarEntry, :count).by(1)
      expect(rule.reload.fired_at).to be_present
    end

    it "fires when reader returns above threshold" do
      rule
      expect {
        described_class.new(metric_reader: reader_class.new(101)).evaluate_all!
      }.to change(CalendarEntry, :count).by(1)
    end

    it "cross_down: does not fire when reader is above threshold" do
      r = create(:milestone_rule, :cross_down, threshold: 10, metric: "ratio")
      expect {
        described_class.new(metric_reader: reader_class.new(20)).evaluate_all!
      }.not_to change(CalendarEntry, :count)
    end

    it "cross_down: fires when reader is at or below threshold" do
      r = create(:milestone_rule, :cross_down, threshold: 10, metric: "ratio")
      expect {
        described_class.new(metric_reader: reader_class.new(5)).evaluate_all!
      }.to change(CalendarEntry, :count).by(1)
    end

    it "skips disabled rules" do
      r = create(:milestone_rule, :disabled, threshold: 100)
      expect {
        described_class.new(metric_reader: reader_class.new(1_000_000)).evaluate_all!
      }.not_to change(CalendarEntry, :count)
    end

    it "skips rules that already fired" do
      r = create(:milestone_rule, :fired, threshold: 100)
      expect {
        described_class.new(metric_reader: reader_class.new(1_000_000)).evaluate_all!
      }.not_to change(CalendarEntry, :count)
    end

    it "iterates every enabled, never-fired rule" do
      rule_a = create(:milestone_rule, threshold: 50)
      rule_b = create(:milestone_rule, threshold: 200)
      expect {
        described_class.new(metric_reader: reader_class.new(100)).evaluate_all!
      }.to change(CalendarEntry, :count).by(1)
      expect(rule_a.reload.fired_at).to be_present
      expect(rule_b.reload.fired_at).to be_nil
    end

    it "rescues per-rule failures so a bad rule does not block others" do
      good = create(:milestone_rule, threshold: 50, name: "good")
      bad = create(:milestone_rule, threshold: 50, name: "bad")
      allow(bad).to receive(:fire!).and_raise("boom")
      allow(MilestoneRule).to receive(:where).and_call_original
      relation = MilestoneRule.where(enabled: true, fired_at: nil)
      allow(MilestoneRule).to receive(:where).with(enabled: true, fired_at: nil).and_return(relation)
      # Stub find_each to yield our rules, returning the bad one with the
      # mocked fire!.
      allow(relation).to receive(:find_each).and_yield(bad).and_yield(good)

      expect {
        described_class.new(metric_reader: reader_class.new(100)).evaluate_all!
      }.not_to raise_error
      # `good` did fire (rule received fire! once via the iteration).
      expect(good.reload.fired_at).to be_present
    end

    it "skips rules whose metric reader returns nil" do
      rule
      reader = double("reader", read: nil)
      expect {
        described_class.new(metric_reader: reader).evaluate_all!
      }.not_to change(CalendarEntry, :count)
    end
  end

  describe "DefaultMetricReader" do
    it "returns nil (Phase 13 wires real reads)" do
      expect(described_class::DefaultMetricReader.new.read(scope_type: :install,
                                                          scope_id: nil,
                                                          metric: "x",
                                                          window: :lifetime)).to be_nil
    end
  end
end
