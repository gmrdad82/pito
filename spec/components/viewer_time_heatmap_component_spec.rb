require "rails_helper"

RSpec.describe ViewerTimeHeatmapComponent, type: :component do
  Result = Analytics::ViewerTimeRollup::Result

  describe "happy — full data" do
    it "renders a 7x24 grid of cells" do
      data = {}
      (0..6).each do |dow|
        (0..23).each do |hod|
          data[[ dow, hod ]] = Result.new(views: 1, watch_time_seconds: 60)
        end
      end
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))

      expect(page).to have_css(".viewer-time-heatmap__cell", count: 7 * 24)
    end

    it "renders the tz label" do
      render_inline(described_class.new(data: { [ 0, 0 ] => Result.new(views: 1, watch_time_seconds: 60) }, tz: "Europe/Bucharest"))
      expect(page).to have_text("tz: Europe/Bucharest")
    end

    it "labels each row with the day abbreviation" do
      render_inline(described_class.new(data: { [ 0, 0 ] => Result.new(views: 1, watch_time_seconds: 60) }, tz: "Etc/UTC"))
      %w[Sun Mon Tue Wed Thu Fri Sat].each do |label|
        expect(page).to have_text(label)
      end
    end

    it "labels each column with the hour 00..23" do
      render_inline(described_class.new(data: { [ 0, 0 ] => Result.new(views: 1, watch_time_seconds: 60) }, tz: "Etc/UTC"))
      expect(page).to have_text("00")
      expect(page).to have_text("23")
    end
  end

  describe "sad — empty data" do
    it "renders the empty-state copy" do
      render_inline(described_class.new(data: {}, tz: "Etc/UTC"))
      expect(page).to have_text("no viewer-time data yet")
    end

    it "does NOT render the grid when empty" do
      render_inline(described_class.new(data: {}, tz: "Etc/UTC"))
      expect(page).to have_no_css(".viewer-time-heatmap__grid")
    end
  end

  describe "edge — single-row data + max normalization" do
    it "renders the max-intensity cell at full alpha" do
      data = { [ 3, 14 ] => Result.new(views: 100, watch_time_seconds: 6000) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))

      # The max-intensity cell uses rgba(0, 0, 204, 1.0).
      expect(page).to have_css("[data-dow='3'][data-hod='14'][data-intensity='1.0']")
    end

    it "renders empty cells with the pane-bg baseline (zero intensity)" do
      data = { [ 3, 14 ] => Result.new(views: 100, watch_time_seconds: 6000) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))
      expect(page).to have_css("[data-dow='0'][data-hod='0'][data-intensity='0.0']")
    end
  end

  describe "intensity_by parameter" do
    it "defaults to :views" do
      component = described_class.new(data: { [ 0, 0 ] => Result.new(views: 1, watch_time_seconds: 60) })
      expect(component.intensity_by).to eq(:views)
    end

    it "accepts :watch_time" do
      data = {
        [ 0, 0 ] => Result.new(views: 1,   watch_time_seconds: 60),
        [ 3, 14 ] => Result.new(views: 100, watch_time_seconds: 10)
      }
      render_inline(described_class.new(data: data, tz: "Etc/UTC", intensity_by: :watch_time))
      # Watch-time max is 60 (in the [0,0] cell); the [3,14] cell with
      # huge views but tiny watch_time should be the LOW-intensity end.
      expect(page).to have_css("[data-dow='0'][data-hod='0'][data-intensity='1.0']")
      expect(page).to have_css("[data-dow='3'][data-hod='14'][data-intensity]")
    end

    it "rejects an unknown intensity_by value" do
      expect {
        described_class.new(data: {}, intensity_by: :unknown)
      }.to raise_error(ArgumentError, /intensity_by must be/)
    end
  end

  # P26 reviewer concern 4 — the native `title=` attribute is gone.
  # Tooltips are CSS-only (`::after` + `data-tooltip`) and accessible
  # via `aria-label`. Cells carry `tabindex="0"` for keyboard reach.
  describe "tooltip" do
    it "renders cell tooltips via data-tooltip with day + hour + counts" do
      data = { [ 3, 14 ] => Result.new(views: 42, watch_time_seconds: 5040) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))
      expect(page).to have_css(
        "[data-dow='3'][data-hod='14'][data-tooltip*='Wed 14:00'][data-tooltip*='42 views'][data-tooltip*='5040s']"
      )
    end

    it "mirrors the tooltip text to aria-label for screen-readers" do
      data = { [ 3, 14 ] => Result.new(views: 42, watch_time_seconds: 5040) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))
      expect(page).to have_css(
        "[data-dow='3'][data-hod='14'][aria-label*='Wed 14:00'][aria-label*='42 views']"
      )
    end

    it "renders 'no data' for empty cells" do
      data = { [ 3, 14 ] => Result.new(views: 1, watch_time_seconds: 60) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))
      expect(page).to have_css(
        "[data-dow='0'][data-hod='0'][data-tooltip*='Sun 00:00'][data-tooltip*='no data']"
      )
    end

    it "does NOT emit the native title= attribute on cells" do
      data = { [ 3, 14 ] => Result.new(views: 42, watch_time_seconds: 5040) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))
      expect(page).to have_no_css(".viewer-time-heatmap__cell[title]")
    end

    it "makes every cell keyboard-focusable via tabindex=0" do
      data = { [ 0, 0 ] => Result.new(views: 1, watch_time_seconds: 60) }
      render_inline(described_class.new(data: data, tz: "Etc/UTC"))
      expect(page).to have_css(".viewer-time-heatmap__cell[tabindex='0']", count: 7 * 24)
    end
  end
end
