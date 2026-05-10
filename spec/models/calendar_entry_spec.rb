require "rails_helper"

RSpec.describe CalendarEntry, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video).optional }
    it { is_expected.to belong_to(:game).optional }
    it { is_expected.to belong_to(:channel).optional }
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to belong_to(:parent_entry).optional }
    it { is_expected.to belong_to(:milestone_rule).optional }
    it { is_expected.to belong_to(:created_by_user).class_name("User").optional }
    it { is_expected.to have_many(:child_entries).class_name("CalendarEntry") }
  end

  describe "enums" do
    it "round-trips entry_type via the public API" do
      entry = build(:calendar_entry, :custom)
      entry.entry_type = "milestone_manual"
      expect(entry.entry_type).to eq("milestone_manual")
      expect(CalendarEntry.entry_types["milestone_manual"]).to eq(5)
    end

    it "round-trips source via the public API" do
      entry = build(:calendar_entry, :custom)
      entry.source = "auto"
      expect(entry.source).to eq("auto")
      expect(CalendarEntry.sources["auto"]).to eq(2)
    end

    it "round-trips state via the public API" do
      entry = build(:calendar_entry, :custom)
      entry.state = "occurred"
      expect(entry.state).to eq("occurred")
      expect(CalendarEntry.states["occurred"]).to eq(1)
    end

    it "release_precision is integer-backed and prefixed" do
      entry = build(:calendar_entry, :game_release)
      entry.release_precision = "month"
      expect(entry.release_precision_month?).to be(true)
      expect(CalendarEntry.release_precisions["tba"]).to eq(4)
    end
  end

  describe "validations" do
    subject { build(:calendar_entry, :custom) }

    describe "title" do
      it "is required" do
        subject.title = ""
        expect(subject).not_to be_valid
        expect(subject.errors[:title]).to be_present
      end

      it "rejects 256-char titles (boundary)" do
        subject.title = "a" * 256
        expect(subject).not_to be_valid
      end

      it "accepts a 255-char title (boundary)" do
        subject.title = "a" * 255
        expect(subject).to be_valid
      end

      it "accepts a 1-char title (boundary)" do
        subject.title = "x"
        expect(subject).to be_valid
      end
    end

    describe "description" do
      it "is optional" do
        subject.description = nil
        expect(subject).to be_valid
      end

      it "rejects 5001-char descriptions (boundary)" do
        subject.description = "x" * 5001
        expect(subject).not_to be_valid
      end

      it "accepts 5000-char descriptions (boundary)" do
        subject.description = "x" * 5000
        expect(subject).to be_valid
      end
    end

    describe "timezone" do
      it "rejects an unknown IANA name" do
        subject.timezone = "Mars/Olympus"
        expect(subject).not_to be_valid
        expect(subject.errors[:timezone]).to be_present
      end

      it "accepts a real IANA name" do
        subject.timezone = "Europe/Madrid"
        expect(subject).to be_valid
      end

      it "accepts UTC" do
        subject.timezone = "UTC"
        expect(subject).to be_valid
      end
    end

    describe "ends_at" do
      it "is OK as nil" do
        subject.ends_at = nil
        expect(subject).to be_valid
      end

      it "is OK when equal to starts_at" do
        subject.ends_at = subject.starts_at
        expect(subject).to be_valid
      end

      it "is OK when after starts_at" do
        subject.ends_at = subject.starts_at + 1.hour
        expect(subject).to be_valid
      end

      it "is rejected when before starts_at" do
        subject.ends_at = subject.starts_at - 1.hour
        expect(subject).not_to be_valid
        expect(subject.errors[:ends_at]).to be_present
      end
    end

    describe "derived entries require source_ref" do
      it "rejects a derived entry with blank source_ref" do
        entry = build(:calendar_entry, :video_published)
        entry.source_ref = nil
        expect(entry).not_to be_valid
        expect(entry.errors[:source_ref]).to be_present
      end

      it "rejects an auto entry with blank source_ref" do
        entry = build(:calendar_entry, :milestone_auto)
        entry.source_ref = nil
        expect(entry).not_to be_valid
      end

      it "accepts a manual entry with blank source_ref" do
        entry = build(:calendar_entry, :milestone_manual)
        entry.source_ref = nil
        expect(entry).to be_valid
      end
    end

    describe "purchase_planned requires parent_entry_id" do
      it "rejects when parent_entry_id is blank" do
        entry = build(:calendar_entry, :purchase_planned)
        entry.parent_entry = nil
        expect(entry).not_to be_valid
        expect(entry.errors[:parent_entry_id]).to be_present
      end
    end

    describe "milestone_auto requires milestone_rule_id" do
      it "rejects when milestone_rule_id is blank" do
        entry = build(:calendar_entry, :milestone_auto)
        entry.milestone_rule = nil
        expect(entry).not_to be_valid
        expect(entry.errors[:milestone_rule_id]).to be_present
      end
    end
  end

  describe "cross-reference validator" do
    it "channel_published happy with channel_id only" do
      entry = build(:calendar_entry, :channel_published)
      expect(entry).to be_valid
    end

    it "channel_published sad with video_id set" do
      entry = build(:calendar_entry, :channel_published)
      entry.video = create(:video)
      expect(entry).not_to be_valid
      expect(entry.errors[:video_id]).to be_present
    end

    it "video_published happy with video_id only" do
      entry = build(:calendar_entry, :video_published)
      expect(entry).to be_valid
    end

    it "video_published sad with game_id set" do
      entry = build(:calendar_entry, :video_published)
      entry.game = create(:game)
      expect(entry).not_to be_valid
    end

    it "video_scheduled happy with video_id only" do
      entry = build(:calendar_entry, :video_scheduled)
      expect(entry).to be_valid
    end

    it "video_scheduled sad with parent_entry_id set" do
      entry = build(:calendar_entry, :video_scheduled)
      entry.parent_entry = create(:calendar_entry, :game_release)
      expect(entry).not_to be_valid
    end

    it "game_release happy with game_id" do
      entry = build(:calendar_entry, :game_release)
      expect(entry).to be_valid
    end

    it "game_release happy with game_id nil (pre-IGDB)" do
      entry = build(:calendar_entry, :game_release)
      entry.game = nil
      expect(entry).to be_valid
    end

    it "game_release sad with parent_entry_id set" do
      entry = build(:calendar_entry, :game_release)
      entry.parent_entry = create(:calendar_entry, :game_release)
      expect(entry).not_to be_valid
    end

    it "purchase_planned happy with parent_entry_id + optional game_id" do
      entry = build(:calendar_entry, :purchase_planned)
      entry.game = create(:game)
      expect(entry).to be_valid
    end

    it "milestone_manual happy with no FKs except optional project_id" do
      entry = build(:calendar_entry, :milestone_manual)
      entry.project = create(:project)
      expect(entry).to be_valid
    end

    it "milestone_manual sad with video_id set" do
      entry = build(:calendar_entry, :milestone_manual)
      entry.video = create(:video)
      expect(entry).not_to be_valid
    end

    it "milestone_auto happy with milestone_rule_id" do
      entry = build(:calendar_entry, :milestone_auto)
      expect(entry).to be_valid
    end

    it "custom happy with no FKs" do
      entry = build(:calendar_entry, :custom)
      expect(entry).to be_valid
    end

    it "custom sad with video_id set" do
      entry = build(:calendar_entry, :custom)
      entry.video = create(:video)
      expect(entry).not_to be_valid
    end
  end

  describe "metadata sanitation" do
    it "strips unknown keys on save" do
      entry = build(:calendar_entry, :custom)
      entry.metadata = { "tags" => %w[a b], "evil" => 1 }
      entry.valid?
      expect(entry.metadata).to eq("tags" => %w[a b])
    end

    it "preserves user_overrides" do
      entry = build(:calendar_entry, :video_published)
      entry.metadata = { "user_overrides" => { "note" => "n1" } }
      entry.valid?
      expect(entry.metadata["user_overrides"]).to eq("note" => "n1")
    end
  end

  describe "read-only enforcement" do
    let!(:tz_setting) { AppSetting.find_or_create_by!(key: "timezone_seed") { |s| s.value = "stub" } }

    let(:derived) do
      create(:calendar_entry, :video_published)
    end

    it "blocks a normal update! to a derived entry's title" do
      derived.title = "hijacked"
      expect(derived.save).to be(false)
      expect(derived.errors[:base]).to be_present
      expect(derived.reload.title).not_to eq("hijacked")
    end

    it "allows a metadata.user_overrides change" do
      meta = derived.metadata.deep_dup
      meta["user_overrides"] = { "note" => "added" }
      derived.metadata = meta
      expect(derived.save).to be(true)
      expect(derived.reload.metadata["user_overrides"]).to eq("note" => "added")
    end

    it "allows manual entry rewrites freely" do
      manual = create(:calendar_entry, :custom)
      manual.title = "new title"
      expect(manual.save).to be(true)
    end

    it "Calendar::Derivation can bypass via the `bypass_readonly` flag" do
      # The service writes through the bypass; simulate by setting
      # the flag directly on the model instance.
      derived.bypass_readonly = true
      derived.title = "service-driven update"
      expect(derived.save).to be(true)
    end
  end

  describe "scopes" do
    let(:t0) { Time.zone.parse("2026-03-01 00:00:00 UTC") }

    describe ".in_range" do
      it "returns entries whose [starts_at, ends_at) overlaps [a, b)" do
        e1 = create(:calendar_entry, :custom, starts_at: t0 + 5.days, ends_at: t0 + 7.days)
        e2 = create(:calendar_entry, :custom, starts_at: t0 + 2.days, ends_at: nil)
        _outside = create(:calendar_entry, :custom, starts_at: t0 + 30.days)
        result = CalendarEntry.in_range(t0 + 1.day, t0 + 10.days)
        expect(result).to include(e1, e2)
        expect(result.count).to eq(2)
      end

      it "treats null ends_at as point-in-time" do
        inside = create(:calendar_entry, :custom, starts_at: t0 + 3.days)
        outside = create(:calendar_entry, :custom, starts_at: t0 + 100.days)
        result = CalendarEntry.in_range(t0, t0 + 10.days)
        expect(result).to include(inside)
        expect(result).not_to include(outside)
      end
    end

    describe ".upcoming_releases" do
      it "returns only future game_release entries, ordered ascending" do
        future = create(:calendar_entry, :game_release, starts_at: 30.days.from_now)
        past = create(:calendar_entry, :game_release, starts_at: 30.days.ago)
        not_release = create(:calendar_entry, :custom)
        result = CalendarEntry.upcoming_releases
        expect(result).to include(future)
        expect(result).not_to include(past, not_release)
      end
    end

    describe ".upcoming_releases_without_purchase" do
      it "excludes releases that have a child purchase_planned" do
        with_purchase = create(:calendar_entry, :game_release, starts_at: 30.days.from_now)
        without_purchase = create(:calendar_entry, :game_release, starts_at: 60.days.from_now)
        create(:calendar_entry, :purchase_planned, parent_entry: with_purchase)
        result = CalendarEntry.upcoming_releases_without_purchase
        expect(result).to include(without_purchase)
        expect(result).not_to include(with_purchase)
      end
    end

    describe ".recent_milestones" do
      it "returns both manual and auto milestones in the window" do
        manual = create(:calendar_entry, :milestone_manual, starts_at: 5.days.ago)
        auto = create(:calendar_entry, :milestone_auto, starts_at: 5.days.ago)
        old = create(:calendar_entry, :milestone_manual, starts_at: 60.days.ago)
        result = CalendarEntry.recent_milestones
        expect(result).to include(manual, auto)
        expect(result).not_to include(old)
      end
    end

    describe ".visible" do
      it "hides cancelled and superseded by default" do
        scheduled = create(:calendar_entry, :custom)
        cancelled = create(:calendar_entry, :custom, :cancelled)
        superseded = create(:calendar_entry, :custom, :superseded)
        result = CalendarEntry.visible
        expect(result).to include(scheduled)
        expect(result).not_to include(cancelled, superseded)
      end
    end
  end

  describe "stamp_install_timezone" do
    before { AppSetting.delete_all }

    it "lifts the install-level timezone for new entries without explicit tz" do
      AppSetting.create!(key: "max_panes", value: "5", timezone: "Europe/Madrid")
      entry = CalendarEntry.new(
        title: "x", starts_at: 1.day.from_now,
        entry_type: :custom, source: :manual, state: :scheduled
      )
      entry.timezone = nil
      entry.valid?
      expect(entry.timezone).to eq("Europe/Madrid")
    end

    it "keeps an explicit timezone" do
      AppSetting.create!(key: "max_panes", value: "5", timezone: "Europe/Madrid")
      entry = build(:calendar_entry, :custom, timezone: "America/New_York")
      entry.valid?
      expect(entry.timezone).to eq("America/New_York")
    end

    it "falls back to UTC when no AppSetting exists" do
      entry = CalendarEntry.new(
        title: "x", starts_at: 1.day.from_now,
        entry_type: :custom, source: :manual, state: :scheduled
      )
      entry.timezone = nil
      entry.valid?
      expect(entry.timezone).to eq("UTC")
    end
  end

  describe "time zones / DST" do
    it "round-trips Europe/Madrid on the spring-forward day" do
      tz = "Europe/Madrid"
      # 2026 spring-forward: Sun Mar 29 02:00 → 03:00 in Europe/Madrid.
      # We stamp 04:00 local (post-shift) which is unambiguous.
      local_time = Time.find_zone(tz).local(2026, 3, 29, 4, 0, 0)
      entry = create(:calendar_entry, :custom, starts_at: local_time, timezone: tz)
      expect(entry.starts_at.in_time_zone(tz).hour).to eq(4)
    end

    it "preserves a leap-year Feb 29 entry" do
      local_time = Time.find_zone("UTC").local(2024, 2, 29, 12, 0, 0)
      entry = create(:calendar_entry, :custom, starts_at: local_time, timezone: "UTC")
      result = CalendarEntry.in_range(
        Time.find_zone("UTC").local(2024, 2, 1),
        Time.find_zone("UTC").local(2024, 3, 1)
      )
      expect(result).to include(entry)
    end

    it "handles year-boundary Europe/Madrid entries" do
      tz = "Europe/Madrid"
      # Dec 31 23:30 Europe/Madrid is 22:30 UTC (Madrid is UTC+1 in winter).
      local_time = Time.find_zone(tz).local(2026, 12, 31, 23, 30, 0)
      entry = create(:calendar_entry, :custom, starts_at: local_time, timezone: tz)
      expect(entry.starts_at.utc.day).to eq(31)
      expect(entry.starts_at.utc.month).to eq(12)
    end
  end

  describe "predicates" do
    it "#derived_or_auto?" do
      derived = build(:calendar_entry, :video_published)
      auto = build(:calendar_entry, :milestone_auto)
      manual = build(:calendar_entry, :custom)
      expect(derived.derived_or_auto?).to be(true)
      expect(auto.derived_or_auto?).to be(true)
      expect(manual.derived_or_auto?).to be(false)
    end

    it "#read_only?" do
      derived = build(:calendar_entry, :video_published)
      manual = build(:calendar_entry, :custom)
      expect(derived.read_only?).to be(true)
      expect(manual.read_only?).to be(false)
    end
  end
end
