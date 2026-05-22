# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::DateTimeComponent, type: :component do
  # 2026-05-22 is a Friday — wday 5
  let(:fixed_time) { Time.new(2026, 5, 22, 12, 34, 56) }

  describe "rendering — default future_notifications: 0" do
    subject(:component) { described_class.new(now: fixed_time) }

    it "renders the canonical lowercase format `fri may 22 12:34:56`" do
      render_inline(component)
      expect(page).to have_css("span.sb-clock.tui-date-time", text: "fri may 22 12:34:56")
    end

    it "carries both Stimulus controllers (tui-date-time + tui-transition)" do
      render_inline(component)
      span = page.find("span.sb-clock")
      controllers = span["data-controller"].to_s.split(/\s+/)
      expect(controllers).to include("tui-date-time", "tui-transition")
    end

    it "exposes the formatted value as tui-transition's value attribute" do
      render_inline(component)
      expect(page).to have_css(
        "[data-tui-transition-value-value='fri may 22 12:34:56']"
      )
    end

    it "carries data-tui-transition-color-value='muted' when future_notifications: 0" do
      render_inline(component)
      expect(page).to have_css("[data-tui-transition-color-value='muted']")
    end

    it "carries data-tui-transition-active-color-value='accent'" do
      render_inline(component)
      expect(page).to have_css("[data-tui-transition-active-color-value='accent']")
    end

    it "wires the tui-date-time outlet to the colocated tui-transition controller" do
      render_inline(component)
      expect(page).to have_css(
        "[data-tui-date-time-tui-transition-outlet='.tui-date-time']"
      )
    end

    it "preserves the status-bar target attribute" do
      render_inline(component)
      expect(page).to have_css("[data-tui-status-bar-target='clock']")
    end
  end

  describe "rendering — future_notifications > 0" do
    subject(:component) { described_class.new(now: fixed_time, future_notifications: 3) }

    it "flips color to 'accent' when future notifications are present" do
      render_inline(component)
      expect(page).to have_css("[data-tui-transition-color-value='accent']")
    end

    it "still carries active_color='accent' so the controller can crossfade" do
      render_inline(component)
      expect(page).to have_css("[data-tui-transition-active-color-value='accent']")
    end
  end

  describe ".format" do
    it "maps weekdays to lowercase 3-letter abbreviations" do
      # 2026-05-17 is a Sunday → wday 0
      expect(described_class.format(Time.new(2026, 5, 17, 0, 0, 0))).to start_with("sun ")
      # 2026-05-18 Monday
      expect(described_class.format(Time.new(2026, 5, 18, 0, 0, 0))).to start_with("mon ")
      # 2026-05-19 Tuesday
      expect(described_class.format(Time.new(2026, 5, 19, 0, 0, 0))).to start_with("tue ")
      # 2026-05-20 Wednesday
      expect(described_class.format(Time.new(2026, 5, 20, 0, 0, 0))).to start_with("wed ")
      # 2026-05-21 Thursday
      expect(described_class.format(Time.new(2026, 5, 21, 0, 0, 0))).to start_with("thu ")
      # 2026-05-22 Friday
      expect(described_class.format(Time.new(2026, 5, 22, 0, 0, 0))).to start_with("fri ")
      # 2026-05-23 Saturday
      expect(described_class.format(Time.new(2026, 5, 23, 0, 0, 0))).to start_with("sat ")
    end

    it "maps every month to its lowercase 3-letter abbreviation" do
      expected = %w[jan feb mar apr may jun jul aug sep oct nov dec]
      (1..12).each do |month_index|
        formatted = described_class.format(Time.new(2026, month_index, 15, 0, 0, 0))
        expect(formatted.split(" ")[1]).to eq(expected[month_index - 1])
      end
    end

    it "zero-pads hours, minutes, and seconds" do
      expect(described_class.format(Time.new(2026, 1, 5, 9, 3, 7))).to eq("mon jan 5 09:03:07")
    end

    it "produces the canonical example `fri may 22 12:34:56`" do
      expect(described_class.format(fixed_time)).to eq("fri may 22 12:34:56")
    end
  end
end
