# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::TimeToBeatComponent do
  let(:game) do
    build_stubbed(:game,
                  ttb_main_seconds:          50 * 3600,
                  ttb_extras_seconds:        100 * 3600,
                  ttb_completionist_seconds: 200 * 3600)
  end

  describe "SAMPLE_HOURS" do
    it "is the documented triplet" do
      expect(described_class::SAMPLE_HOURS).to eq(main: 31, extras: 71, completionist: 124)
    end
  end

  describe "PILLAR_KEYS" do
    it "is [:main, :extras, :completionist]" do
      expect(described_class::PILLAR_KEYS).to eq(%i[main extras completionist])
    end
  end

  describe "#hours" do
    it "reads IGDB seconds from the game" do
      comp = described_class.new(game: game)
      expect(comp.hours).to eq(main: 50, extras: 100, completionist: 200)
    end

    it "falls back to SAMPLE_HOURS when all ttb seconds are zero" do
      bare = build_stubbed(:game,
                            ttb_main_seconds: 0,
                            ttb_extras_seconds: 0,
                            ttb_completionist_seconds: 0)
      comp = described_class.new(game: bare)
      expect(comp.hours).to eq(described_class::SAMPLE_HOURS)
    end

    it "falls back to SAMPLE_HOURS when all ttb seconds are nil" do
      bare = build_stubbed(:game,
                            ttb_main_seconds: nil,
                            ttb_extras_seconds: nil,
                            ttb_completionist_seconds: nil)
      comp = described_class.new(game: bare)
      expect(comp.hours).to eq(described_class::SAMPLE_HOURS)
    end

    it "lets an explicit hours kwarg trump both game and sample" do
      bare = build_stubbed(:game, ttb_main_seconds: 0, ttb_extras_seconds: 0, ttb_completionist_seconds: 0)
      comp = described_class.new(game: bare, hours: { main: 7, extras: 14, completionist: 21 })
      expect(comp.hours).to eq(main: 7, extras: 14, completionist: 21)
    end
  end

  describe "#max_x" do
    it "is completionist * 1.05 rounded" do
      comp = described_class.new(game: game, footage_hours: 50)
      # max(200, 50, 10) = 200; 200 * 1.05 = 210
      expect(comp.max_x).to eq(210)
    end
  end

  describe "#position" do
    it "projects a value onto the 0..100 axis" do
      comp = described_class.new(game: game, footage_hours: 50)
      # main 50 / 210 = 23.81 %
      expect(comp.position(50)).to be_within(0.01).of(23.810)
    end

    it "clamps to 100" do
      comp = described_class.new(game: game)
      expect(comp.position(999)).to eq(100.0)
    end
  end

  describe "#label_for" do
    it "formats a positive pillar as 'Nh'" do
      comp = described_class.new(game: game)
      expect(comp.label_for(:main)).to include("50")
    end

    it "returns em-dash for zero" do
      comp = described_class.new(game: game, hours: { main: 0, extras: 10, completionist: 20 })
      expect(comp.label_for(:main)).to eq("—")
    end
  end

  describe "#tick_overlays" do
    it "returns 4 entries (3 pillars + footage)" do
      comp = described_class.new(game: game, footage_hours: 50)
      expect(comp.tick_overlays.length).to eq(4)
    end

    it "includes the correct keys" do
      comp = described_class.new(game: game, footage_hours: 50)
      keys = comp.tick_overlays.map { |t| t[:key] }
      expect(keys).to eq(%i[main extras completionist footage])
    end
  end

  describe "#pillar_label_data" do
    it "returns 3 entries in pillar key order" do
      comp = described_class.new(game: game)
      keys = comp.pillar_label_data.map { |d| d[:key] }
      expect(keys).to eq(%i[main extras completionist])
    end

    it "nudges colliding labels apart" do
      # main 31h / 775 = 4.0 %, extras 71h / 775 = 9.16 % → gap < 10 % → collision
      crimson = build_stubbed(:game,
                                ttb_main_seconds:          31  * 3600,
                                ttb_extras_seconds:        71  * 3600,
                                ttb_completionist_seconds: 738 * 3600)
      comp = described_class.new(game: crimson, footage_hours: 0)
      data = comp.pillar_label_data

      expect(data[0][:nudge]).to eq(:left)
      expect(data[1][:nudge]).to eq(:right)
      expect(data[2][:nudge]).to be_nil
    end
  end

  describe "#gradient_break_positions" do
    it "returns p1..p6" do
      comp = described_class.new(game: game, footage_hours: 0)
      breaks = comp.gradient_break_positions
      expect(breaks.keys).to eq(%i[p1 p2 p3 p4 p5 p6])
      # All values should be percentage strings ending in '%'
      breaks.each_value do |v|
        expect(v).to end_with("%")
      end
    end
  end

  describe "HEAT_THRESHOLDS" do
    it "has 4 stops (0 / 10 / 40 / 100 hours)" do
      hours = described_class::HEAT_THRESHOLDS.map(&:first)
      expect(hours).to eq([ 0, 10, 40, 100 ])
    end

    it "sources every stop from theme accent vars (no literal hex)" do
      colors = described_class::HEAT_THRESHOLDS.map(&:last)
      colors.each do |c|
        expect(c).to include("var(--accent-")
        expect(c).not_to match(/#[0-9a-fA-F]{3,8}\b/)
      end
    end

    it "maps low/some/commitment/insanity to the documented accent expression" do
      colors = described_class::HEAT_THRESHOLDS.map(&:last)
      expect(colors[0]).to eq("var(--accent-green)")                                                # low — green
      expect(colors[1]).to eq("color-mix(in oklch, var(--accent-green), var(--accent-yellow))")     # some — lime
      expect(colors[2]).to eq("color-mix(in oklch, var(--accent-orange) 60%, var(--accent-yellow))") # commitment — amber
      expect(colors[3]).to eq("color-mix(in oklch, var(--accent-red), var(--accent-purple))")        # insanity — pink
    end
  end

  describe "#gradient_stops" do
    it "returns a CSS stop string sourced from theme accents" do
      comp = described_class.new(game: game)
      stops = comp.gradient_stops
      expect(stops).to include("var(--accent-green)")                                          # green — low
      expect(stops).to include("color-mix(in oklch, var(--accent-green), var(--accent-yellow))") # lime  — some
      expect(stops).to include("var(--accent-orange)")                                         # amber — commitment
      expect(stops).to include("var(--accent-purple)")                                         # pink  — insanity
    end

    it "contains no literal hex colors" do
      comp = described_class.new(game: game)
      expect(comp.gradient_stops).not_to match(/#[0-9a-fA-F]{3,8}\b/)
    end

    it "ends with 100% so the bar extends fully" do
      comp = described_class.new(game: game)
      expect(comp.gradient_stops).to end_with("100%")
    end

    it "projects small max_x so lime/amber/pink are clamped" do
      # max_x ≈ 10h → 10h threshold projects to 100%, 40h and 100h > 100%
      tiny = described_class.new(hours: { main: 5, extras: 8, completionist: 10 }, footage_hours: 0)
      stops = tiny.gradient_stops
      # The first stop (0h → green) should be at 0% (any precision)
      expect(stops).to match(/\Avar\(--accent-green\) 0(\.0+)?%/)
    end

    it "projects large max_x (Crimson-Desert scale) so pink dominates" do
      # completionist = 738h → max_x ≈ 775h; 100h projects to ~12.9%
      crimson = described_class.new(
        hours:         { main: 31, extras: 71, completionist: 738 },
        footage_hours: 0
      )
      stops = crimson.gradient_stops
      # The 100h pink stop is the red→purple mix; grab the percentage that
      # immediately follows it (color-mix expressions contain commas, so we
      # can't naively split on ", ").
      pink = "color-mix(in oklch, var(--accent-red), var(--accent-purple))"
      pct = stops[/#{Regexp.escape(pink)} ([\d.]+)%/, 1]&.to_f
      expect(pct).to be < 20.0
    end
  end

  describe "render_inline — gradient structure" do
    it "renders the pito-ttb__fill element" do
      comp = described_class.new(game: game)
      html = render_inline(comp).to_html
      expect(html).to include("pito-ttb__fill")
    end

    it "renders the bar with an inline adaptive gradient sourced from theme accents" do
      comp = described_class.new(game: game)
      html = render_inline(comp).to_html
      expect(html).to include("linear-gradient(to right")
      expect(html).to include("var(--accent-green)")  # low end
      expect(html).to include("var(--accent-purple)") # insanity end (red→purple mix)
    end

    it "renders four ticks (3 pillars + footage)" do
      comp = described_class.new(game: game, footage_hours: 50)
      html = render_inline(comp).to_html
      expect(html.scan("pito-ttb__tick").size).to eq(4)
    end
  end
end
