require "rails_helper"

RSpec.describe NotificationScheduler do
  let(:scheduler) { described_class.new }

  describe "#perform with calendar_declarations" do
    context "game_release with day precision and no purchase" do
      let!(:game_entry) do
        create(:calendar_entry, :game_release,
               release_precision: :day, starts_at: 7.days.from_now)
      end

      it "materializes T-7 (and T-1 once ripe) declarations" do
        # T-7 is "now" so it's ripe; T-1 is 6 days away — not ripe.
        # T-0 is also 7 days away — not ripe yet.
        expect { scheduler.perform }.to change { Notification.count }.by(1)
        notif = Notification.last
        expect(notif.event_type).to eq("game_release_upcoming")
        expect(notif.source_calendar_entry_id).to eq(game_entry.id)
      end

      it "is idempotent — re-run does not create duplicates" do
        scheduler.perform
        expect { scheduler.perform }.not_to change(Notification, :count)
      end

      it "does not materialize a future declaration" do
        # Push the entry far enough that no offset is ripe.
        game_entry.update!(starts_at: 60.days.from_now)
        # Wipe any prior rows from previous setup.
        Notification.delete_all
        expect { scheduler.perform }.not_to change(Notification, :count)
      end
    end

    context "game_release in the past" do
      it "materializes the day-of declaration" do
        entry = create(:calendar_entry, :game_release,
                       release_precision: :day, starts_at: 1.minute.ago)
        Notification.delete_all
        expect { scheduler.perform }.to change(Notification, :count).by_at_least(1)
        kinds = Notification.where(source_calendar_entry_id: entry.id).pluck(:event_type)
        expect(kinds).to include("game_release_today")
      end
    end

    context "game_release with notify_anyway=false purchase_planned child" do
      it "suppresses pre-release reminders" do
        parent = create(:calendar_entry, :game_release,
                        release_precision: :day, starts_at: 0.days.from_now + 1.minute)
        create(:calendar_entry, :purchase_planned, parent_entry: parent, notify_anyway: false)
        Notification.delete_all
        scheduler.perform
        kinds = Notification.where(source_calendar_entry_id: parent.id).pluck(:event_type)
        expect(kinds).not_to include("game_release_upcoming")
      end
    end

    context "game_release with notify_anyway=true purchase_planned child" do
      it "fires the day-of declaration normally" do
        parent = create(:calendar_entry, :game_release,
                        release_precision: :day, starts_at: 30.seconds.from_now)
        create(:calendar_entry, :purchase_planned, parent_entry: parent, notify_anyway: true)
        Notification.delete_all
        scheduler.perform
        kinds = Notification.where(source_calendar_entry_id: parent.id).pluck(:event_type)
        expect(kinds).to include("game_release_today")
      end
    end

    context "game_release with quarter precision" do
      it "produces no offsets" do
        entry = create(:calendar_entry, :game_release,
                       release_precision: :quarter, starts_at: 30.days.from_now)
        Notification.delete_all
        scheduler.perform
        expect(Notification.where(source_calendar_entry_id: entry.id).count).to eq(0)
      end
    end

    context "milestone_auto" do
      it "materializes one milestone_reached row at starts_at" do
        rule = create(:milestone_rule)
        entry = create(:calendar_entry, :milestone_auto, milestone_rule: rule,
                                                          starts_at: 1.hour.ago)
        Notification.delete_all
        expect { scheduler.perform }.to change(Notification, :count).by(1)
        notif = Notification.last
        expect(notif.event_type).to eq("milestone_reached")
        expect(notif.source_calendar_entry_id).to eq(entry.id)
        expect(notif.source_milestone_rule_id).to eq(rule.id)
      end
    end
  end

  describe "#perform with occurred entries" do
    it "materializes a calendar_entry_firing row for milestone_manual that flipped to occurred" do
      entry = create(:calendar_entry, :milestone_manual,
                     starts_at: 1.minute.ago, state: :occurred)
      Notification.delete_all
      expect { scheduler.perform }.to change {
        Notification.where(event_type: "calendar_entry_firing", source_calendar_entry_id: entry.id).count
      }.by(1)
    end

    it "materializes a calendar_entry_firing row for custom that flipped to occurred" do
      entry = create(:calendar_entry, :custom,
                     starts_at: 1.minute.ago, state: :occurred)
      Notification.delete_all
      expect { scheduler.perform }.to change {
        Notification.where(event_type: "calendar_entry_firing", source_calendar_entry_id: entry.id).count
      }.by(1)
    end

    it "does NOT re-materialize on the second pass" do
      entry = create(:calendar_entry, :custom,
                     starts_at: 1.minute.ago, state: :occurred)
      Notification.delete_all
      scheduler.perform
      expect { scheduler.perform }
        .not_to change(Notification, :count)
    end

    it "does NOT materialize for entries that are still scheduled" do
      create(:calendar_entry, :milestone_manual,
             starts_at: 1.minute.ago, state: :scheduled)
      Notification.delete_all
      scheduler.perform
      expect(Notification.where(event_type: "calendar_entry_firing").count).to eq(0)
    end
  end

  describe "#perform delivery enqueue" do
    let!(:rule)  { create(:milestone_rule) }
    let!(:entry) do
      create(:calendar_entry, :milestone_auto,
             milestone_rule: rule, starts_at: 1.hour.ago)
    end

    before { Notification.delete_all; NotificationDeliver.clear }

    it "enqueues an in_app delivery for every new row" do
      scheduler.perform
      args = NotificationDeliver.jobs.map { |j| j["args"] }
      expect(args.any? { |(_, kind)| kind == "in_app" }).to be(true)
    end

    it "enqueues a discord delivery only when AppSetting.discord_delivery_enabled?" do
      allow(AppSetting).to receive(:discord_delivery_enabled?).and_return(true)
      allow(AppSetting).to receive(:slack_delivery_enabled?).and_return(false)
      scheduler.perform
      kinds = NotificationDeliver.jobs.map { |j| j["args"][1] }
      expect(kinds).to include("discord")
      expect(kinds).not_to include("slack")
    end

    it "enqueues a slack delivery only when AppSetting.slack_delivery_enabled?" do
      allow(AppSetting).to receive(:discord_delivery_enabled?).and_return(false)
      allow(AppSetting).to receive(:slack_delivery_enabled?).and_return(true)
      scheduler.perform
      kinds = NotificationDeliver.jobs.map { |j| j["args"][1] }
      expect(kinds).to include("slack")
      expect(kinds).not_to include("discord")
    end

    it "does NOT enqueue on the find path of find_or_create_by!" do
      scheduler.perform
      NotificationDeliver.clear
      scheduler.perform
      expect(NotificationDeliver.jobs).to be_empty
    end
  end
end
