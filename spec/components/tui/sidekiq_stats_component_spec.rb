# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::SidekiqStatsComponent, type: :component do
  describe "structure" do
    subject(:component) { described_class.new(busy: 3, enqueued: 5, retry_count: 2) }

    before { render_inline(component) }

    it "mounts the parent tui-sidekiq-stats controller on the row" do
      expect(page).to have_css(".tui-sidekiq-row[data-controller~='tui-sidekiq-stats']")
    end

    it "renders three cells" do
      expect(page).to have_css(".tui-sidekiq-cell", count: 3)
    end

    it "marks each cell with its name" do
      %w[busy enqueued retry].each do |name|
        expect(page).to have_css(".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='#{name}']")
      end
    end

    it "wires each cell with the tui-transition controller" do
      expect(page).to have_css(".tui-sidekiq-cell[data-controller~='tui-transition']", count: 3)
    end
  end

  describe "prefix data attribute" do
    subject(:component) { described_class.new(busy: 1, enqueued: 1, retry_count: 1) }

    before { render_inline(component) }

    {
      "busy" => "b",
      "enqueued" => "e",
      "retry" => "r"
    }.each do |name, prefix|
      it "sets tui-transition-prefix-value to #{prefix.inspect} for #{name}" do
        expect(page).to have_css(
          ".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='#{name}']" \
          "[data-tui-transition-prefix-value='#{prefix}']"
        )
      end
    end

    it "renders the prefix glyph inside .cell-prefix" do
      expect(page).to have_css(".tui-sidekiq-cell .cell-prefix", count: 3)
    end
  end

  describe "color mapping" do
    subject(:component) { described_class.new(busy: 1, enqueued: 1, retry_count: 1) }

    before { render_inline(component) }

    it "sets base color :muted on every cell" do
      expect(page).to have_css(".tui-sidekiq-cell[data-tui-transition-color-value='muted']", count: 3)
    end

    it "maps busy → success" do
      expect(page).to have_css(
        ".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='busy']" \
        "[data-tui-transition-active-color-value='success']"
      )
    end

    it "maps enqueued → warn" do
      expect(page).to have_css(
        ".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='enqueued']" \
        "[data-tui-transition-active-color-value='warn']"
      )
    end

    it "maps retry → danger" do
      expect(page).to have_css(
        ".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='retry']" \
        "[data-tui-transition-active-color-value='danger']"
      )
    end
  end

  describe "width-lock — short format + 4-char right pad" do
    {
      0          => "0   ",
      32         => "32  ",
      111        => "111 ",
      999        => "999 ",
      1_000      => "1k  ",
      22_345     => "22k ",
      899_000    => "899k",
      1_000_000  => "1M  "
    }.each do |raw, padded|
      it "displays #{raw} as #{padded.inspect} (busy cell)" do
        render_inline(described_class.new(busy: raw))
        expect(page).to have_css(
          ".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='busy']" \
          "[data-tui-transition-value-value='#{padded}']"
        )
      end
    end

    it "renders the padded value as visible text alongside the prefix" do
      render_inline(described_class.new(busy: 3))
      # The 4-char-padded value appears in the rendered DOM after `.cell-prefix`.
      expect(page).to have_text("3   ")
    end
  end

  describe "legacy `retry:` kwarg compatibility" do
    it "still accepts retry: instead of retry_count:" do
      render_inline(described_class.new(busy: 0, enqueued: 0, retry: 7))
      expect(page).to have_css(
        ".tui-sidekiq-cell[data-tui-sidekiq-stats-cell-name-value='retry']" \
        "[data-tui-transition-value-value='7   ']"
      )
    end
  end
end
