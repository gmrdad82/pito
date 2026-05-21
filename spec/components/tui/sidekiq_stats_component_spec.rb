require "rails_helper"

RSpec.describe Tui::SidekiqStatsComponent, type: :component do
  describe "default render" do
    it "renders three muted-zero cells when no kwargs are passed" do
      render_inline(described_class.new)
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "e0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
      expect(page).to have_no_css(".sb-sk-cell.sk-b")
      expect(page).to have_no_css(".sb-sk-cell.sk-e")
      expect(page).to have_no_css(".sb-sk-cell.sk-r")
    end
  end

  describe "color states" do
    it "applies sk-zero (muted) for any cell whose value is 0" do
      render_inline(described_class.new(busy: 0, enqueued: 5, retry: 0))
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-e",    text: "e5")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
    end

    it "applies sk-b / sk-e / sk-r when each value is positive" do
      render_inline(described_class.new(busy: 1, enqueued: 2, retry: 4))
      expect(page).to have_css(".sb-sk-cell.sk-b", text: "b1")
      expect(page).to have_css(".sb-sk-cell.sk-e", text: "e2")
      expect(page).to have_css(".sb-sk-cell.sk-r", text: "r4")
    end

    it "renders large values correctly" do
      render_inline(described_class.new(busy: 12, enqueued: 33, retry: 7))
      expect(page).to have_css(".sb-sk-cell.sk-b", text: "b12")
      expect(page).to have_css(".sb-sk-cell.sk-e", text: "e33")
      expect(page).to have_css(".sb-sk-cell.sk-r", text: "r7")
    end
  end

  describe "Stimulus targets (cable wiring contract)" do
    it "carries data-tui-status-bar-target attrs on container + each cell" do
      render_inline(described_class.new)
      expect(page).to have_css('[data-tui-status-bar-target="sidekiq"]')
      expect(page).to have_css('[data-tui-status-bar-target="sidekiqBusy"]')
      expect(page).to have_css('[data-tui-status-bar-target="sidekiqEnqueued"]')
      expect(page).to have_css('[data-tui-status-bar-target="sidekiqRetry"]')
    end
  end

  describe "edge cases" do
    it "coerces nil counts to 0" do
      render_inline(described_class.new(busy: nil, enqueued: nil, retry: nil))
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "b0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "e0")
      expect(page).to have_css(".sb-sk-cell.sk-zero", text: "r0")
    end

    it "does NOT render a scheduled cell (only b/e/r are shown)" do
      render_inline(described_class.new(busy: 1, enqueued: 2, retry: 3))
      expect(page).to have_no_css(".sb-sk-cell", text: /s\d/)
    end
  end
end
