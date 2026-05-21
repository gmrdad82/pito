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

    # Phase 15 security audit F2 — race window between the model-level
    # `fired_at IS NULL` check and the calendar_entry insert.
    describe "concurrent firing (F2 race-condition guard)" do
      it "the partial unique index prevents two milestone_auto entries for one rule" do
        # Direct manual insert path simulates a sibling fire! that
        # already committed. The second insert must trip the partial
        # unique index `index_calendar_entries_unique_milestone_rule`.
        rule.update!(fired_at: Time.current)
        CalendarEntry.create!(
          entry_type: :milestone_auto,
          source: :auto,
          state: :occurred,
          title: rule.name,
          starts_at: Time.current,
          all_day: false,
          timezone: "UTC",
          milestone_rule_id: rule.id,
          source_ref: { milestone_rule_id: rule.id, metric_value_at_fire: 1 },
          metadata: { metric_value_at_fire: 1, user_overrides: {} }
        )

        expect {
          CalendarEntry.create!(
            entry_type: :milestone_auto,
            source: :auto,
            state: :occurred,
            title: rule.name,
            starts_at: Time.current,
            all_day: false,
            timezone: "UTC",
            milestone_rule_id: rule.id,
            source_ref: { milestone_rule_id: rule.id, metric_value_at_fire: 2 },
            metadata: { metric_value_at_fire: 2, user_overrides: {} }
          )
        }.to raise_error(ActiveRecord::RecordNotUnique)

        expect(
          CalendarEntry.where(milestone_rule_id: rule.id, entry_type: :milestone_auto).count
        ).to eq(1)
      end

      it "the partial unique index does NOT block a second auto entry on a DIFFERENT rule" do
        # The index is scoped per `milestone_rule_id`. Two distinct
        # rules can each have their own milestone_auto entry.
        rule.update!(fired_at: Time.current)
        CalendarEntry.create!(
          entry_type: :milestone_auto,
          source: :auto,
          state: :occurred,
          title: rule.name,
          starts_at: Time.current,
          all_day: false,
          timezone: "UTC",
          milestone_rule_id: rule.id,
          source_ref: { milestone_rule_id: rule.id, metric_value_at_fire: 1 },
          metadata: { metric_value_at_fire: 1, user_overrides: {} }
        )

        other_rule = create(:milestone_rule, name: "other", fired_at: Time.current)
        expect {
          CalendarEntry.create!(
            entry_type: :milestone_auto,
            source: :auto,
            state: :occurred,
            title: other_rule.name,
            starts_at: Time.current,
            all_day: false,
            timezone: "UTC",
            milestone_rule_id: other_rule.id,
            source_ref: { milestone_rule_id: other_rule.id, metric_value_at_fire: 5 },
            metadata: { metric_value_at_fire: 5, user_overrides: {} }
          )
        }.not_to raise_error
      end

      it "fire! rescues RecordNotUnique and returns the rule when a sibling already committed" do
        # Simulate a concurrent fire!: the calendar_entry insert trips
        # the partial unique index, and the sibling caller's `fired_at`
        # is visible on the next reload. Under RSpec's transactional
        # fixtures we can't truly cross-transaction; we stub `reload`
        # to return a rule with `fired_at` already stamped — exactly
        # the production state after the sibling's commit lands.
        sibling_fired_at = 5.minutes.ago
        allow(CalendarEntry).to receive(:create!).and_raise(
          ActiveRecord::RecordNotUnique, "duplicate key value"
        )
        allow(rule).to receive(:reload) do
          rule.fired_at = sibling_fired_at
          rule
        end

        result = rule.fire!(metric_value: 99)
        expect(result).to eq(rule)
        expect(rule.fired_at).to be_within(2.seconds).of(sibling_fired_at)
      end

      it "fire! re-raises RecordNotUnique when fired_at is still nil after reload" do
        # Defensive branch: if the index trips but `fired_at` was never
        # persisted (e.g., the surrounding transaction rolled back the
        # update! and the only thing left is the raw exception), let
        # the exception bubble so the caller can retry.
        allow(CalendarEntry).to receive(:create!).and_raise(
          ActiveRecord::RecordNotUnique, "duplicate"
        )
        # The default reload will pull a row whose `fired_at` was just
        # rolled back by the savepoint -> nil. The rescue branch must
        # re-raise.
        expect { rule.fire!(metric_value: 99) }.to raise_error(ActiveRecord::RecordNotUnique)
      end
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
      Pito::Calendar::MilestoneEvaluator.new(metric_reader: reader).evaluate_all!
      expect(rule.reload.fired_at).to be_nil
    end

    it "flipping a disabled rule back to enabled does not re-fire after fired_at is set" do
      rule = create(:milestone_rule, :fired, enabled: false)
      rule.update!(enabled: true)
      reader = double("reader", read: 1_000_000)
      Pito::Calendar::MilestoneEvaluator.new(metric_reader: reader).evaluate_all!
      # fired_at stays the same
      expect(rule.reload.fired_at).to be_within(1.second).of(rule.fired_at)
    end
  end
end
