require "rails_helper"

RSpec.describe BlockedLocationsHelper, type: :helper do
  describe "#blocked_location_source_badge" do
    it "uppercases the web source" do
      row = build(:blocked_location, source_surface: :web)
      expect(helper.blocked_location_source_badge(row)).to eq("WEB")
    end

    it "uppercases the tui source" do
      row = build(:blocked_location, source_surface: :tui)
      expect(helper.blocked_location_source_badge(row)).to eq("TUI")
    end

    it "uppercases the mcp source" do
      row = build(:blocked_location, source_surface: :mcp)
      expect(helper.blocked_location_source_badge(row)).to eq("MCP")
    end
  end

  describe "#blocked_location_state_label" do
    it "returns 'active' on a live row" do
      row = build(:blocked_location)
      expect(helper.blocked_location_state_label(row)).to eq("active")
    end

    it "returns 'unblocked' on a soft-unblocked row" do
      row = build(:blocked_location, :unblocked)
      expect(helper.blocked_location_state_label(row)).to eq("unblocked")
    end
  end

  describe "#blocked_location_state_css" do
    it "returns an empty string for active rows (no special styling)" do
      row = build(:blocked_location)
      expect(helper.blocked_location_state_css(row)).to eq("")
    end

    it "returns 'text-muted' for soft-unblocked rows" do
      row = build(:blocked_location, :unblocked)
      expect(helper.blocked_location_state_css(row)).to eq("text-muted")
    end
  end

  describe "#blocked_location_reason_label" do
    it "echoes a free-text reason" do
      row = build(:blocked_location, reason: "auto-block: threshold exceeded")
      expect(helper.blocked_location_reason_label(row)).to eq("auto-block: threshold exceeded")
    end

    it "falls back to '—' when the reason is blank" do
      row = build(:blocked_location, reason: nil)
      expect(helper.blocked_location_reason_label(row)).to eq("—")
    end
  end

  describe "#blocked_location_age" do
    let(:now) { Time.utc(2026, 5, 11, 12, 0, 0) }

    it "returns 'now' for sub-minute deltas" do
      row = build(:blocked_location, blocked_at: now - 30.seconds)
      expect(helper.blocked_location_age(row, now: now)).to eq("now")
    end

    it "returns minutes for sub-hour deltas" do
      row = build(:blocked_location, blocked_at: now - 10.minutes)
      expect(helper.blocked_location_age(row, now: now)).to eq("10m")
    end

    it "returns hours for sub-day deltas" do
      row = build(:blocked_location, blocked_at: now - 5.hours)
      expect(helper.blocked_location_age(row, now: now)).to eq("5h")
    end

    it "returns days for older rows" do
      row = build(:blocked_location, blocked_at: now - 3.days)
      expect(helper.blocked_location_age(row, now: now)).to eq("3d")
    end

    it "returns '—' when blocked_at is missing" do
      row = build(:blocked_location, blocked_at: nil)
      expect(helper.blocked_location_age(row, now: now)).to eq("—")
    end
  end
end
