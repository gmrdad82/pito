# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::DateTimeComponent, type: :component do
  describe "default (no time given)" do
    subject(:component) { described_class.new }

    it "renders without raising" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "renders the em-dash placeholder when no time is passed" do
      render_inline(component)
      expect(page).to have_css("span.sb-clock", text: "—")
    end

    it "carries the Stimulus controller data attribute" do
      render_inline(component)
      expect(page).to have_css("[data-controller='tui-date-time']")
    end

    it "carries the status-bar target attribute" do
      render_inline(component)
      expect(page).to have_css("[data-tui-status-bar-target='clock']")
    end
  end

  describe "with a time passed" do
    # 2026-05-20 is a Wednesday
    let(:fixed_time) { Time.new(2026, 5, 20, 14, 30, 59) }
    subject(:component) { described_class.new(time: fixed_time) }

    it "renders the formatted date-time string" do
      render_inline(component)
      # Day abbreviations and month abbreviations come from WEEKDAYS/MONTHS constants
      # in the component — not from i18n — per the spec contract.
      expect(page).to have_css("span.sb-clock", text: "Wed, May 20 · 14:30:59")
    end

    it "does not render the em-dash placeholder" do
      render_inline(component)
      expect(page).not_to have_css("span.sb-clock", text: "—")
    end
  end

  describe "#formatted" do
    it "returns the em-dash constant when time is nil" do
      expect(described_class.new.formatted).to eq("—")
    end

    it "zero-pads hours, minutes, seconds" do
      # 2026-01-05 is a Monday
      t = Time.new(2026, 1, 5, 9, 3, 7)
      expect(described_class.new(time: t).formatted).to eq("Mon, Jan 5 · 09:03:07")
    end
  end
end
