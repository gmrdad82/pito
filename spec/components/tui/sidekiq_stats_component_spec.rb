# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe Tui::SidekiqStatsComponent, type: :component do
  describe "structure" do
    subject(:component) { described_class.new(busy: 3, enqueued: 5, retry_count: 2) }

    before { render_inline(component) }

    it "renders a single tui-sidekiq-stats span" do
      expect(page).to have_css("span.tui-sidekiq-stats", count: 1)
    end

    it "does NOT render any per-cell legacy elements" do
      expect(page).not_to have_css(".tui-sidekiq-row")
      expect(page).not_to have_css(".tui-sidekiq-cell")
      expect(page).not_to have_css(".cell-prefix")
      expect(page).not_to have_css(".sb-sidekiq")
    end

    it "renders the formatted value as visible text" do
      expect(page).to have_css("span.tui-sidekiq-stats", text: "b3 e5 r2")
    end

    it "mounts both tui-sidekiq-stats AND tui-transition controllers on the host" do
      host = page.find("span.tui-sidekiq-stats")
      controllers = host["data-controller"].split
      expect(controllers).to include("tui-sidekiq-stats")
      expect(controllers).to include("tui-transition")
    end

    it "declares tui-transition as a Stimulus outlet of tui-sidekiq-stats" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-sidekiq-stats-tui-transition-outlet"]).to eq(".tui-sidekiq-stats")
    end
  end

  describe "default (all zeros)" do
    before { render_inline(described_class.new) }

    it "renders 'b0 e0 r0' as visible text" do
      expect(page).to have_css("span.tui-sidekiq-stats", text: "b0 e0 r0")
    end

    it "seeds tui-transition's value to 'b0 e0 r0'" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-value-value"]).to eq("b0 e0 r0")
    end

    it "uses :muted as the base color" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-color-value"]).to eq("muted")
    end

    it "marks every segment inactive in the segments JSON" do
      host = page.find("span.tui-sidekiq-stats")
      segments = JSON.parse(host["data-tui-transition-segments-value"])
      expect(segments.size).to eq(3)
      expect(segments.map { |s| s["active"] }).to all(be false)
    end
  end

  describe "value-driven activation" do
    before { render_inline(described_class.new(busy: 3, enqueued: 0, retry_count: 2)) }

    it "renders the expected formatted string" do
      expect(page).to have_css("span.tui-sidekiq-stats", text: "b3 e0 r2")
    end

    it "seeds tui-transition's value to match" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-value-value"]).to eq("b3 e0 r2")
    end

    it "marks busy + retry active and enqueued inactive in the segments JSON" do
      host = page.find("span.tui-sidekiq-stats")
      segments = JSON.parse(host["data-tui-transition-segments-value"])
      by_name = segments.index_by { |s| s["name"] }
      expect(by_name["busy"]["active"]).to eq(true)
      expect(by_name["enqueued"]["active"]).to eq(false)
      expect(by_name["retry"]["active"]).to eq(true)
    end

    it "encodes contiguous ranges across the formatted string" do
      host = page.find("span.tui-sidekiq-stats")
      segments = JSON.parse(host["data-tui-transition-segments-value"])
      by_name = segments.index_by { |s| s["name"] }
      # "b3 e0 r2"
      # busy: [0, 2)  → "b3"
      # enq:  [3, 5)  → "e0"
      # ret:  [6, 8)  → "r2"
      expect(by_name["busy"]["range"]).to eq([ 0, 2 ])
      expect(by_name["enqueued"]["range"]).to eq([ 3, 5 ])
      expect(by_name["retry"]["range"]).to eq([ 6, 8 ])
    end
  end

  describe "short-format integration" do
    it "displays 1500 as '1k'" do
      render_inline(described_class.new(busy: 1500))
      expect(page).to have_css("span.tui-sidekiq-stats", text: "b1k e0 r0")
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-value-value"]).to eq("b1k e0 r0")
    end

    it "adjusts segment ranges to the short-formatted length" do
      render_inline(described_class.new(busy: 1500))
      host = page.find("span.tui-sidekiq-stats")
      segments = JSON.parse(host["data-tui-transition-segments-value"])
      by_name = segments.index_by { |s| s["name"] }
      # "b1k e0 r0"
      # busy: [0, 3) → "b1k"
      # enq:  [4, 6) → "e0"
      # ret:  [7, 9) → "r0"
      expect(by_name["busy"]["range"]).to eq([ 0, 3 ])
      expect(by_name["enqueued"]["range"]).to eq([ 4, 6 ])
      expect(by_name["retry"]["range"]).to eq([ 7, 9 ])
    end
  end

  describe "controller order on data-controller" do
    it "lists tui-sidekiq-stats before tui-transition" do
      render_inline(described_class.new)
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-controller"]).to eq("tui-sidekiq-stats tui-transition")
    end
  end

  describe "legacy `retry:` kwarg compatibility" do
    it "still accepts retry: instead of retry_count:" do
      render_inline(described_class.new(busy: 0, enqueued: 0, retry: 7))
      expect(page).to have_css("span.tui-sidekiq-stats", text: "b0 e0 r7")
    end
  end
end
