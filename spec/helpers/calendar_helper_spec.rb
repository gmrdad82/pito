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

  # Phase 15 calendar UX restructure — the kind-filter csv contract.
  describe "#calendar_active_kinds" do
    it "treats nil (no `types` param) as :all (default = all checked)" do
      expect(helper.calendar_active_kinds(nil)).to eq(:all)
    end

    it "treats an empty string as :none (all unchecked)" do
      expect(helper.calendar_active_kinds("")).to eq(:none)
    end

    it "treats whitespace-only / comma-only input as :none" do
      expect(helper.calendar_active_kinds(" , , ")).to eq(:none)
    end

    it "returns the explicit subset when valid labels are present" do
      expect(helper.calendar_active_kinds("video,custom")).to eq(%w[video custom])
    end

    it "drops unknown labels silently" do
      expect(helper.calendar_active_kinds("video,zorblax")).to eq(%w[video])
    end

    it "returns :none when every label is invalid" do
      expect(helper.calendar_active_kinds("zorblax,blarp")).to eq(:none)
    end

    it "rejects the synthetic `all` label (it is UI-only, not a CSV member)" do
      expect(helper.calendar_active_kinds("all")).to eq(:none)
    end
  end

  describe "#calendar_kind_checked?" do
    it "is true for every label when default state (no param)" do
      CalendarHelper::CALENDAR_KIND_LABELS.each do |label|
        expect(helper.calendar_kind_checked?(label, nil)).to be(true)
      end
    end

    it "is false for every label when types= empty" do
      CalendarHelper::CALENDAR_KIND_LABELS.each do |label|
        expect(helper.calendar_kind_checked?(label, "")).to be(false)
      end
    end

    it "is true only for explicit subset members" do
      expect(helper.calendar_kind_checked?("video", "video,custom")).to be(true)
      expect(helper.calendar_kind_checked?("game", "video,custom")).to be(false)
    end
  end

  describe "#calendar_all_kinds_checked?" do
    it "is true on the default state (no param)" do
      expect(helper.calendar_all_kinds_checked?(nil)).to be(true)
    end

    it "is false when any kind is missing from the csv" do
      expect(helper.calendar_all_kinds_checked?("video,custom")).to be(false)
    end

    it "is true when every kind is in the csv" do
      expect(helper.calendar_all_kinds_checked?(CalendarHelper::CALENDAR_KIND_LABELS.join(","))).to be(true)
    end

    it "is false on the empty-types ('all unchecked') state" do
      expect(helper.calendar_all_kinds_checked?("")).to be(false)
    end
  end

  describe "#calendar_kind_chip_href" do
    it "from default state, the [video] chip drops video and lists the other 4" do
      href = helper.calendar_kind_chip_href("video", nil, current_params: {})
      expect(href).to eq("?types=game%2Cmilestone%2Cpurchase%2Ccustom")
    end

    it "from :none state, the [video] chip turns video on" do
      href = helper.calendar_kind_chip_href("video", "", current_params: {})
      expect(href).to eq("?types=video")
    end

    it "from explicit subset, clicking a checked label removes it" do
      href = helper.calendar_kind_chip_href("video", "video,game", current_params: {})
      expect(href).to eq("?types=game")
    end

    it "from explicit subset, clicking an unchecked label adds it" do
      href = helper.calendar_kind_chip_href("game", "video", current_params: {})
      expect(href).to eq("?types=video%2Cgame")
    end

    it "preserves other params (page, state, source)" do
      href = helper.calendar_kind_chip_href("video", nil, current_params: { "state" => "all", "page" => "2" })
      pairs = href.delete_prefix("?").split("&").sort
      expect(pairs).to include("page=2", "state=all")
      expect(pairs.find { |p| p.start_with?("types=") }).to be_present
    end

    it "drops controller/action/year/month from the preserved params" do
      href = helper.calendar_kind_chip_href("video", nil,
        current_params: { "controller" => "calendar/month", "action" => "show", "year" => "2026", "month" => "5" })
      expect(href).not_to include("controller=")
      expect(href).not_to include("action=")
      expect(href).not_to include("year=")
      expect(href).not_to include("month=")
    end
  end

  describe "#calendar_all_kinds_chip_href" do
    it "from default checked state, sets types= to empty (uncheck all)" do
      href = helper.calendar_all_kinds_chip_href(nil, current_params: {})
      expect(href).to eq("?types=")
    end

    it "from :none state, drops the types param (all checked default URL)" do
      href = helper.calendar_all_kinds_chip_href("", current_params: {})
      expect(href).to eq("?")
    end

    it "from a partial subset, drops the types param (so master flips to checked)" do
      href = helper.calendar_all_kinds_chip_href("video,custom", current_params: {})
      expect(href).to eq("?")
    end

    it "from full-CSV state, sets types= to empty (master is checked, click unchecks)" do
      href = helper.calendar_all_kinds_chip_href(CalendarHelper::CALENDAR_KIND_LABELS.join(","), current_params: {})
      expect(href).to eq("?types=")
    end

    it "preserves other params (page, state, source)" do
      href = helper.calendar_all_kinds_chip_href(nil, current_params: { "state" => "all", "page" => "2" })
      pairs = href.delete_prefix("?").split("&").sort
      expect(pairs).to include("page=2", "state=all", "types=")
    end
  end
end
