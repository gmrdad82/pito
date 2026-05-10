require "rails_helper"

RSpec.describe Calendar::NotificationDispatchDeclaration do
  describe ".declarations_for" do
    context "game_release" do
      it "with release_precision=day and no purchase, returns T-7 / T-1 / T-0 + game_release_today" do
        entry = create(:calendar_entry, :game_release, release_precision: :day, starts_at: 30.days.from_now)
        decls = described_class.declarations_for(entry)
        kinds = decls.map { |d| d[:kind] }
        # T-7 + T-1 + T-0 (default-on offsets) and game_release_today
        expect(kinds).to include("game_release_upcoming")
        expect(kinds).to include("game_release_today")
        # game_release_upcoming pre-release reminders (offsets 7, 1)
        # plus the day-of (offset 0) skipped from pre-release branch
        # since `next [] if offset.zero?`.
        upcoming = decls.select { |d| d[:kind] == "game_release_upcoming" }
        expect(upcoming.size).to eq(2)
      end

      it "with release_precision=day and a child purchase_planned (notify_anyway=false), suppresses pre-release reminders" do
        entry = create(:calendar_entry, :game_release, release_precision: :day, starts_at: 30.days.from_now)
        create(:calendar_entry, :purchase_planned, parent_entry: entry, notify_anyway: false)
        decls = described_class.declarations_for(entry)
        kinds = decls.map { |d| d[:kind] }
        expect(kinds).not_to include("game_release_upcoming")
        expect(kinds).to include("game_release_today")
      end

      it "with release_precision=day and a child purchase_planned (notify_anyway=true), keeps all" do
        entry = create(:calendar_entry, :game_release, release_precision: :day, starts_at: 30.days.from_now)
        create(:calendar_entry, :purchase_planned, parent_entry: entry, notify_anyway: true)
        decls = described_class.declarations_for(entry)
        kinds = decls.map { |d| d[:kind] }
        expect(kinds).to include("game_release_upcoming", "game_release_today")
      end

      it "with release_precision=quarter, returns no declarations" do
        entry = create(:calendar_entry, :game_release, release_precision: :quarter, starts_at: 30.days.from_now)
        decls = described_class.declarations_for(entry)
        expect(decls).to eq([])
      end

      it "with release_precision=year, returns no declarations" do
        entry = create(:calendar_entry, :game_release, release_precision: :year, starts_at: 30.days.from_now)
        expect(described_class.declarations_for(entry)).to eq([])
      end

      it "with release_precision=tba, returns no declarations" do
        entry = create(:calendar_entry, :game_release, release_precision: :tba, starts_at: 30.days.from_now)
        expect(described_class.declarations_for(entry)).to eq([])
      end
    end

    context "video_scheduled" do
      it "returns one declaration at starts_at - 1h" do
        entry = create(:calendar_entry, :video_scheduled, starts_at: 5.days.from_now)
        decls = described_class.declarations_for(entry)
        expect(decls.size).to eq(1)
        expect(decls.first[:kind]).to eq("video_scheduled_publishing_soon")
        expect(decls.first[:fires_at]).to be_within(1.second).of(entry.starts_at - 1.hour)
        expect(decls.first[:severity]).to eq("info")
      end
    end

    context "milestone_auto" do
      it "returns one declaration at starts_at, severity success" do
        rule = create(:milestone_rule)
        entry = create(:calendar_entry, :milestone_auto, milestone_rule: rule)
        decls = described_class.declarations_for(entry)
        expect(decls.size).to eq(1)
        expect(decls.first).to include(kind: "milestone_reached", severity: "success")
      end
    end

    context "other entry types" do
      %i[channel_published video_published purchase_planned milestone_manual custom].each do |trait|
        it "returns [] for #{trait}" do
          entry = build(:calendar_entry, trait)
          expect(described_class.declarations_for(entry)).to eq([])
        end
      end
    end
  end
end
