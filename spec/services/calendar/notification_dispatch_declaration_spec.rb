require "rails_helper"

RSpec.describe Calendar::NotificationDispatchDeclaration do
  describe ".declarations_for" do
    context "game_release" do
      # 2026-05-12 — the `game_release_upcoming` pre-release reminder
      # track (T-7 / T-1) was dropped per user direction. Only the
      # day-of `game_release_today` declaration survives.
      it "with release_precision=day, returns only game_release_today" do
        entry = build_stubbed(:calendar_entry, :game_release, release_precision: :day, starts_at: 30.days.from_now)
        decls = described_class.declarations_for(entry)
        kinds = decls.map { |d| d[:kind] }
        expect(kinds).to eq([ "game_release_today" ])
      end

      it "with release_precision=day and any purchase_planned child, still fires game_release_today" do
        entry = build_stubbed(:calendar_entry, :game_release, release_precision: :day, starts_at: 30.days.from_now)
        # The service does not look at children — the child existence
        # is irrelevant to the declarations computation. Skip creating
        # the child to keep this test stubbed.
        decls = described_class.declarations_for(entry)
        kinds = decls.map { |d| d[:kind] }
        expect(kinds).to eq([ "game_release_today" ])
      end

      it "with release_precision=quarter, returns no declarations" do
        entry = build_stubbed(:calendar_entry, :game_release, release_precision: :quarter, starts_at: 30.days.from_now)
        decls = described_class.declarations_for(entry)
        expect(decls).to eq([])
      end

      it "with release_precision=year, returns no declarations" do
        entry = build_stubbed(:calendar_entry, :game_release, release_precision: :year, starts_at: 30.days.from_now)
        expect(described_class.declarations_for(entry)).to eq([])
      end

      it "with release_precision=tba, returns no declarations" do
        entry = build_stubbed(:calendar_entry, :game_release, release_precision: :tba, starts_at: 30.days.from_now)
        expect(described_class.declarations_for(entry)).to eq([])
      end
    end

    context "video_scheduled" do
      it "returns one declaration at starts_at - 1h" do
        entry = build_stubbed(:calendar_entry, :video_scheduled, starts_at: 5.days.from_now)
        decls = described_class.declarations_for(entry)
        expect(decls.size).to eq(1)
        expect(decls.first[:kind]).to eq("video_scheduled_publishing_soon")
        expect(decls.first[:fires_at]).to be_within(1.second).of(entry.starts_at - 1.hour)
        expect(decls.first[:severity]).to eq("info")
      end
    end

    context "milestone_auto" do
      it "returns one declaration at starts_at, severity success" do
        rule = build_stubbed(:milestone_rule)
        entry = build_stubbed(:calendar_entry, :milestone_auto, milestone_rule: rule)
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
