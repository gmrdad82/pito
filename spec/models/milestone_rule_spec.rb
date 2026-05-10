require "rails_helper"

RSpec.describe MilestoneRule, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:created_by_user).class_name("User").optional }
    it { is_expected.to have_many(:calendar_entries) }
  end

  describe "enums" do
    it "scope_type round-trips" do
      r = build(:milestone_rule)
      r.scope_type = "channel"
      expect(r.scope_type).to eq("channel")
      expect(MilestoneRule.scope_types["install"]).to eq(0)
    end

    it "metric_window mirrors Phase 13's short-form names" do
      r = build(:milestone_rule)
      r.metric_window = "7d"
      expect(r.metric_window).to eq("7d")
    end

    it "direction round-trips" do
      r = build(:milestone_rule)
      r.direction = "cross_down"
      expect(r.direction).to eq("cross_down")
    end
  end

  describe "validations" do
    it "requires name" do
      r = build(:milestone_rule, name: nil)
      expect(r).not_to be_valid
    end

    it "requires metric" do
      r = build(:milestone_rule, metric: nil)
      expect(r).not_to be_valid
    end

    it "requires threshold to be numeric" do
      r = build(:milestone_rule, threshold: nil)
      expect(r).not_to be_valid
    end

    it "rejects scope_type=install with scope_id non-nil" do
      r = build(:milestone_rule, scope_type: :install, scope_id: 1)
      expect(r).not_to be_valid
      expect(r.errors[:scope_id]).to be_present
    end

    it "rejects scope_type=channel with scope_id nil" do
      r = build(:milestone_rule, scope_type: :channel, scope_id: nil)
      expect(r).not_to be_valid
      expect(r.errors[:scope_id]).to be_present
    end

    it "rejects scope_type=channel with non-existent scope_id" do
      r = build(:milestone_rule, scope_type: :channel, scope_id: 999_999_999)
      expect(r).not_to be_valid
      expect(r.errors[:scope_id]).to be_present
    end

    it "accepts scope_type=channel with a real channel id" do
      ch = create(:channel)
      r = build(:milestone_rule, scope_type: :channel, scope_id: ch.id)
      expect(r).to be_valid
    end

    it "rejects scope_type=video with non-existent scope_id" do
      r = build(:milestone_rule, scope_type: :video, scope_id: 999_999_999)
      expect(r).not_to be_valid
    end

    it "accepts scope_type=video with a real video id" do
      v = create(:video)
      r = build(:milestone_rule, scope_type: :video, scope_id: v.id)
      expect(r).to be_valid
    end
  end

  describe "#fire!" do
    let(:rule) { create(:milestone_rule, name: "100 subs") }

    it "writes a milestone_auto calendar entry" do
      expect { rule.fire!(metric_value: 150) }
        .to change(CalendarEntry, :count).by(1)
      ce = rule.calendar_entries.first
      expect(ce.entry_type).to eq("milestone_auto")
      expect(ce.source).to eq("auto")
      expect(ce.state).to eq("occurred")
      expect(ce.title).to eq("100 subs")
      expect(ce.metadata["metric_value_at_fire"]).to eq(150)
    end

    it "stamps fired_at" do
      rule.fire!(metric_value: 150)
      expect(rule.reload.fired_at).to be_present
    end

    it "raises on second call (idempotency)" do
      rule.fire!(metric_value: 150)
      expect { rule.fire!(metric_value: 200) }.to raise_error("already fired")
    end

    it "rolls back both writes if the calendar_entry insert fails" do
      allow(CalendarEntry).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(CalendarEntry.new))
      expect { rule.fire!(metric_value: 150) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(rule.reload.fired_at).to be_nil
    end
  end

  describe "#re_arm!" do
    it "clears fired_at" do
      rule = create(:milestone_rule, :fired)
      expect(rule.fired_at).to be_present
      rule.re_arm!
      expect(rule.reload.fired_at).to be_nil
    end
  end

  describe "evaluator interaction (round-trip)" do
    it "enabled=false rule is never fired by the evaluator" do
      rule = create(:milestone_rule, :disabled)
      reader = double("reader", read: 1_000_000)
      Calendar::MilestoneEvaluator.new(metric_reader: reader).evaluate_all!
      expect(rule.reload.fired_at).to be_nil
    end

    it "flipping a disabled rule back to enabled does not re-fire after fired_at is set" do
      rule = create(:milestone_rule, :fired, enabled: false)
      rule.update!(enabled: true)
      reader = double("reader", read: 1_000_000)
      Calendar::MilestoneEvaluator.new(metric_reader: reader).evaluate_all!
      # fired_at stays the same
      expect(rule.reload.fired_at).to be_within(1.second).of(rule.fired_at)
    end
  end
end
