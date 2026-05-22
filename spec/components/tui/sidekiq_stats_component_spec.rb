# frozen_string_literal: true

require "rails_helper"
require "json"

RSpec.describe Tui::SidekiqStatsComponent, type: :component do
  # Canonical brand prefix sourced from i18n (tui.sidekiq.label).
  # Cached once per spec run so assertions stay readable without
  # re-resolving inline.
  let(:prefix) { I18n.t("tui.sidekiq.label") }

  # Helper to extract the segments-hash-by-name from the rendered host
  # element. Most assertions below use this to keep the spec readable
  # and decoupled from positional ordering of the segments array.
  def segments_by_name
    host = page.find("span.tui-sidekiq-stats")
    JSON.parse(host["data-tui-transition-segments-value"]).index_by { |s| s["name"] }
  end

  describe "structure" do
    subject(:component) { described_class.new(busy: 3, enqueued: 5, retry_count: 2, dead: 1) }

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
      expect(page).to have_css("span.tui-sidekiq-stats", text: "#{prefix} b3 e5 r2 d1")
    end

    it "sources the brand prefix from I18n.t('tui.sidekiq.label')" do
      expect(prefix).to eq("Sidekiq") # canonical brand value lives in the YAML
      expect(page).to have_css("span.tui-sidekiq-stats", text: /\A#{Regexp.escape(prefix)} /)
    end

    it "exposes the prefix as a Stimulus value (data-tui-sidekiq-stats-prefix-value)" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-sidekiq-stats-prefix-value"]).to eq(prefix)
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

    it "renders '<prefix> b0 e0 r0 d0' as visible text" do
      expect(page).to have_css("span.tui-sidekiq-stats", text: "#{prefix} b0 e0 r0 d0")
    end

    it "seeds tui-transition's value to '<prefix> b0 e0 r0 d0'" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-value-value"]).to eq("#{prefix} b0 e0 r0 d0")
    end

    it "uses :muted as the base color" do
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-color-value"]).to eq("muted")
    end

    it "uses the new `color` field (not `active`) on every segment" do
      segments = JSON.parse(page.find("span.tui-sidekiq-stats")["data-tui-transition-segments-value"])
      expect(segments).to all(have_key("color"))
      expect(segments.map { |s| s["name"] }).to eq(%w[busy enqueued retry dead])
      # All zeros → every segment muted.
      expect(segments.map { |s| s["color"] }).to all(eq("muted"))
    end
  end

  describe "concurrency-aware tier coverage" do
    # ─── busy tier ──────────────────────────────────────────────────
    it "busy=0 → muted" do
      render_inline(described_class.new(busy: 0, concurrency: 10))
      expect(segments_by_name["busy"]["color"]).to eq("muted")
    end

    it "busy=5/10 (50% — ratio <= 0.8) → success" do
      render_inline(described_class.new(busy: 5, concurrency: 10))
      expect(segments_by_name["busy"]["color"]).to eq("success")
    end

    it "busy=8/10 (80% — ratio == 0.8 boundary) → success" do
      render_inline(described_class.new(busy: 8, concurrency: 10))
      expect(segments_by_name["busy"]["color"]).to eq("success")
    end

    it "busy=9/10 (90% — 0.8 < ratio < 1.0) → warn" do
      render_inline(described_class.new(busy: 9, concurrency: 10))
      expect(segments_by_name["busy"]["color"]).to eq("warn")
    end

    it "busy=10/10 (100% saturated, enqueued=0) → warn" do
      render_inline(described_class.new(busy: 10, enqueued: 0, concurrency: 10))
      expect(segments_by_name["busy"]["color"]).to eq("warn")
    end

    it "busy=10/10 (100% saturated, enqueued>0 — backpressure) → danger" do
      render_inline(described_class.new(busy: 10, enqueued: 5, concurrency: 10))
      expect(segments_by_name["busy"]["color"]).to eq("danger")
    end

    # ─── enqueued tier ──────────────────────────────────────────────
    it "enqueued=0 → muted" do
      render_inline(described_class.new(enqueued: 0, concurrency: 10))
      expect(segments_by_name["enqueued"]["color"]).to eq("muted")
    end

    it "enqueued=10/10 (1× mult) → success" do
      render_inline(described_class.new(enqueued: 10, concurrency: 10))
      expect(segments_by_name["enqueued"]["color"]).to eq("success")
    end

    it "enqueued=15/10 (1.5× mult — 1 < mult <= 2) → warn" do
      render_inline(described_class.new(enqueued: 15, concurrency: 10))
      expect(segments_by_name["enqueued"]["color"]).to eq("warn")
    end

    it "enqueued=20/10 (2× mult — boundary) → warn" do
      render_inline(described_class.new(enqueued: 20, concurrency: 10))
      expect(segments_by_name["enqueued"]["color"]).to eq("warn")
    end

    it "enqueued=25/10 (2.5× mult — mult > 2) → danger" do
      render_inline(described_class.new(enqueued: 25, concurrency: 10))
      expect(segments_by_name["enqueued"]["color"]).to eq("danger")
    end

    # ─── retry tier (flat) ──────────────────────────────────────────
    it "retry_count=0 → muted" do
      render_inline(described_class.new(retry_count: 0))
      expect(segments_by_name["retry"]["color"]).to eq("muted")
    end

    it "retry_count=1 → danger (flat)" do
      render_inline(described_class.new(retry_count: 1))
      expect(segments_by_name["retry"]["color"]).to eq("danger")
    end

    it "retry_count=999 → danger (flat — any retry is danger)" do
      render_inline(described_class.new(retry_count: 999))
      expect(segments_by_name["retry"]["color"]).to eq("danger")
    end

    # ─── dead tier (flat) ───────────────────────────────────────────
    it "dead=0 → muted" do
      render_inline(described_class.new(dead: 0))
      expect(segments_by_name["dead"]["color"]).to eq("muted")
    end

    it "dead=1 → fatal (flat)" do
      render_inline(described_class.new(dead: 1))
      expect(segments_by_name["dead"]["color"]).to eq("fatal")
    end

    it "dead=5000 → fatal (flat — short-formatted as d5k)" do
      render_inline(described_class.new(dead: 5000))
      expect(segments_by_name["dead"]["color"]).to eq("fatal")
      expect(page).to have_css("span.tui-sidekiq-stats", text: "#{prefix} b0 e0 r0 d5k")
    end
  end

  describe "concurrency coercion safety" do
    it "coerces concurrency=0 to 1 (avoids div-by-zero) — busy=1 reads as ratio=1.0" do
      render_inline(described_class.new(busy: 1, enqueued: 0, concurrency: 0))
      # ratio = 1/1 = 1.0, enqueued = 0 → saturated/no-queue → warn
      expect(segments_by_name["busy"]["color"]).to eq("warn")
    end

    it "coerces a negative concurrency to 1" do
      render_inline(described_class.new(busy: 0, concurrency: -5))
      expect(segments_by_name["busy"]["color"]).to eq("muted")
    end
  end

  describe "range encoding" do
    before { render_inline(described_class.new(busy: 3, enqueued: 0, retry_count: 2, dead: 1)) }

    it "encodes contiguous ranges across the formatted string" do
      by_name = segments_by_name
      # "<prefix> b3 e0 r2 d1"  (offset = prefix.length + 1 space; "Sidekiq"=8)
      offset = prefix.length + 1
      # busy: [offset, offset+2)
      # enq:  [offset+3, offset+5)
      # ret:  [offset+6, offset+8)
      # dead: [offset+9, offset+11)
      expect(by_name["busy"]["range"]).to eq([ offset, offset + 2 ])
      expect(by_name["enqueued"]["range"]).to eq([ offset + 3, offset + 5 ])
      expect(by_name["retry"]["range"]).to eq([ offset + 6, offset + 8 ])
      expect(by_name["dead"]["range"]).to eq([ offset + 9, offset + 11 ])
    end
  end

  describe "short-format integration" do
    it "displays 1500 as '1k'" do
      render_inline(described_class.new(busy: 1500))
      expect(page).to have_css("span.tui-sidekiq-stats", text: "#{prefix} b1k e0 r0 d0")
      host = page.find("span.tui-sidekiq-stats")
      expect(host["data-tui-transition-value-value"]).to eq("#{prefix} b1k e0 r0 d0")
    end

    it "adjusts segment ranges to the short-formatted length" do
      render_inline(described_class.new(busy: 1500))
      by_name = segments_by_name
      # "<prefix> b1k e0 r0 d0"  (offset = prefix.length + 1)
      offset = prefix.length + 1
      # busy: [offset, offset+3)  → "b1k"
      # enq:  [offset+4, offset+6)
      # ret:  [offset+7, offset+9)
      # dead: [offset+10, offset+12)
      expect(by_name["busy"]["range"]).to eq([ offset, offset + 3 ])
      expect(by_name["enqueued"]["range"]).to eq([ offset + 4, offset + 6 ])
      expect(by_name["retry"]["range"]).to eq([ offset + 7, offset + 9 ])
      expect(by_name["dead"]["range"]).to eq([ offset + 10, offset + 12 ])
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
      expect(page).to have_css("span.tui-sidekiq-stats", text: "#{prefix} b0 e0 r7 d0")
      # And the flat tier still applies — retry > 0 → danger.
      expect(segments_by_name["retry"]["color"]).to eq("danger")
    end
  end
end
