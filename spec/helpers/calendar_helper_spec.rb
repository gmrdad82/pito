require "rails_helper"

RSpec.describe CalendarHelper, type: :helper do
  describe "#month_grid_dates" do
    it "returns Monday-first dates spanning the month and trailing days" do
      grid = helper.month_grid_dates(2026, 3)
      # March 1 2026 is a Sunday. Monday-first means leading days from
      # Feb 23 (Mon) through Feb 28 (Sat) + Mar 1 (Sun).
      expect(grid.first).to eq(Date.new(2026, 2, 23))
      # March 31 2026 is a Tuesday. Round up to a 7-multiple.
      expect(grid.length % 7).to eq(0)
      expect(grid).to include(Date.new(2026, 3, 31))
    end

    it "handles February correctly (short month)" do
      grid = helper.month_grid_dates(2026, 2)
      # Feb 1 2026 is a Sunday (in Gregorian calendar). Leading 6 days.
      expect(grid.first).to eq(Date.new(2026, 1, 26))
      expect(grid.length % 7).to eq(0)
    end

    it "handles a leap-year February" do
      grid = helper.month_grid_dates(2024, 2)
      expect(grid).to include(Date.new(2024, 2, 29))
    end
  end

  describe "#entry_chip_glyph" do
    {
      "channel_published" => "c:",
      "video_published"   => "v:",
      "video_scheduled"   => "v?:",
      "game_release"      => "g:",
      "purchase_planned"  => "$:",
      "milestone_manual"  => "m:",
      "milestone_auto"    => "m*:",
      "custom"            => "~:"
    }.each do |type, glyph|
      it "returns '#{glyph}' for #{type}" do
        e = build(:calendar_entry, type.to_sym)
        expect(helper.entry_chip_glyph(e)).to eq(glyph)
      end
    end
  end

  describe "#entry_time_label" do
    it "is empty for all-day entries" do
      e = build(:calendar_entry, :game_release)
      expect(helper.entry_time_label(e)).to eq("")
    end

    it "is HH:MM for timed entries" do
      e = build(:calendar_entry, :custom, all_day: false,
                                          starts_at: Time.zone.parse("2026-05-15 14:30:00 UTC"))
      expect(helper.entry_time_label(e)).to eq("14:30")
    end
  end

  describe "#entry_date_label" do
    it "returns lowercase abbreviated form" do
      e = build(:calendar_entry, :custom,
                starts_at: Time.zone.parse("2026-03-14 10:00:00 UTC"))
      expect(helper.entry_date_label(e)).to eq("mar 14")
    end
  end

  describe "#entry_chip_class" do
    it "embeds the state" do
      e = build(:calendar_entry, :custom, :occurred)
      expect(helper.entry_chip_class(e)).to eq("calendar-entry calendar-entry--occurred")
    end
  end
end
