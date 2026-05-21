require "rails_helper"

RSpec.describe Tui::DateTimeComponent, type: :component do
  describe "default render" do
    it "renders an em-dash placeholder when no time: kwarg is passed" do
      render_inline(described_class.new)
      expect(page).to have_css(".sb-clock", text: "—")
    end
  end

  describe "with explicit time" do
    it "formats a Time as 'Wed, May 20 · 12:34:56'" do
      time = Time.zone.local(2026, 5, 20, 12, 34, 56) # Wednesday
      render_inline(described_class.new(time: time))
      expect(page).to have_css(".sb-clock", text: "Wed, May 20 · 12:34:56")
    end

    it "zero-pads single-digit hours / minutes / seconds" do
      time = Time.zone.local(2026, 1, 5, 3, 4, 5) # Monday
      render_inline(described_class.new(time: time))
      expect(page).to have_css(".sb-clock", text: "Mon, Jan 5 · 03:04:05")
    end

    it "handles each weekday correctly" do
      # Sunday 2026-05-17
      sunday = Time.zone.local(2026, 5, 17, 12, 0, 0)
      render_inline(described_class.new(time: sunday))
      expect(page).to have_css(".sb-clock", text: /^Sun,/)
    end

    it "handles each month correctly (December)" do
      time = Time.zone.local(2026, 12, 1, 9, 0, 0)
      render_inline(described_class.new(time: time))
      expect(page).to have_css(".sb-clock", text: /Dec 1/)
    end
  end

  describe "Stimulus target (cable wiring contract)" do
    it "carries data-tui-status-bar-target=clock so the controller can patch it" do
      render_inline(described_class.new)
      expect(page).to have_css('.sb-clock[data-tui-status-bar-target="clock"]')
    end
  end

  describe "edge cases" do
    it "renders placeholder when explicitly passed time: nil" do
      render_inline(described_class.new(time: nil))
      expect(page).to have_css(".sb-clock", text: "—")
    end
  end
end
