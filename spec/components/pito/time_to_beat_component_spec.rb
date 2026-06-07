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

  describe "partial IGDB TTB (only main — e.g. Crusader Kings 3)" do
    subject(:comp) { described_class.new(hours: { main: 43, extras: 0, completionist: 0 }) }

    it "anchors the lone main pillar to the right (does NOT collapse to 0%)" do
      main = comp.tick_overlays.find { |t| t[:key] == :main }
      expect(main[:position]).to be > 90.0
    end

    it "renders no tick for absent extras / completionist" do
      keys = comp.tick_overlays.map { |t| t[:key] }
      expect(keys).not_to include(:extras, :completionist)
    end

    it "renders only the main value label (absent pillars omitted)" do
      keys = comp.pillar_label_data.map { |d| d[:key] }
      expect(keys).to eq([ :main ])
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

  describe "BAR_CELLS" do
    it "is 40 (each = spans a 2.5% slice of 0..completionist)" do
      expect(described_class::BAR_CELLS).to eq(40)
    end
  end

  describe "#fill_text" do
    it "returns FILL_CELLS = characters (overflow, CSS-clipped to full width)" do
      expect(described_class.new(game: game).fill_text).to eq("=" * described_class::FILL_CELLS)
      expect(described_class::FILL_CELLS).to be >= 100
    end
  end

  describe "#color_axis_max" do
    it "is the completionist hour count" do
      expect(described_class.new(game: game).color_axis_max).to eq(200)
    end

    it "floors at 10h so a tiny game can't divide by zero" do
      tiny = described_class.new(hours: { main: 1, extras: 2, completionist: 3 })
      expect(tiny.color_axis_max).to eq(10)
    end
  end

  describe "#tick_position" do
    let(:comp) { described_class.new(hours: { main: 50, extras: 100, completionist: 200 }) }

    it "always pins completionist to the last-cell midpoint (98.75%)" do
      expect(comp.tick_position(200)).to eq(98.75)
    end

    it "snaps main/extras to their cell midpoints" do
      # main 50/200 = 25% → cell 10 → 26.25%; extras 100/200 = 50% → cell 20 → 51.25%
      expect(comp.tick_position(50)).to eq(26.25)
      expect(comp.tick_position(100)).to eq(51.25)
    end

    it "snaps a zero value to the first cell midpoint (1.25%)" do
      expect(comp.tick_position(0)).to eq(1.25)
    end

    it "clamps a value beyond completionist to 98.75%" do
      expect(comp.tick_position(500)).to eq(98.75)
    end

    it "returns 0 when completionist is zero" do
      bare = described_class.new(hours: { main: 0, extras: 0, completionist: 0 })
      expect(bare.tick_position(5)).to eq(0.0)
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

    it "maps low/some/commitment to the contrast-safe fg-mix, and insanity to the vivid red+purple mix" do
      # The light mids stay wrapped in a fg-mix color-mix so the bar reads on all
      # 18 themes. The insanity/pink end is the un-dimmed red+purple mix: it's the
      # intended bright magenta and the fg wash was muting it (#c0699f vs #f182ae).
      colors = described_class::HEAT_THRESHOLDS.map(&:last)
      expect(colors[0]).to eq("color-mix(in oklch, var(--accent-green) 70%, var(--fg-default))")                                                 # low — green
      expect(colors[1]).to eq("color-mix(in oklch, color-mix(in oklch, var(--accent-green), var(--accent-yellow)) 58%, var(--fg-default))")      # some — lime
      expect(colors[2]).to eq("color-mix(in oklch, color-mix(in oklch, var(--accent-orange) 60%, var(--accent-yellow)) 58%, var(--fg-default))") # commitment — amber
      expect(colors[3]).to eq("color-mix(in oklch, var(--accent-red), var(--accent-purple))")                                                    # insanity — vivid pink
    end
  end

  describe "#gradient_stops" do
    it "returns a CSS stop string sourced from theme accents" do
      comp = described_class.new(game: game)
      stops = comp.gradient_stops
      expect(stops).to include("var(--accent-green)")  # green — low
      expect(stops).to include("var(--accent-yellow)") # lime  — some
      expect(stops).to include("var(--accent-orange)") # amber — commitment
      expect(stops).to include("var(--accent-purple)") # pink  — insanity
      expect(stops).to include("var(--fg-default)")    # T17.1 contrast fg-mix
    end

    it "contains no literal hex colors" do
      comp = described_class.new(game: game)
      expect(comp.gradient_stops).not_to match(/#[0-9a-fA-F]{3,8}\b/)
    end

    it "ends with 100% so the bar extends fully" do
      comp = described_class.new(game: game)
      expect(comp.gradient_stops).to end_with("100%")
    end

    it "projects a small completionist axis so amber/pink clamp away" do
      # color_axis_max = 10h → 40h + 100h thresholds project past 100% and clamp
      tiny = described_class.new(hours: { main: 5, extras: 8, completionist: 10 }, footage_hours: 0)
      stops = tiny.gradient_stops
      # The first stop (0h → green, now wrapped in the T17.1 fg-mix) sits at
      # 0% (any precision).
      green = "color-mix(in oklch, var(--accent-green) 70%, var(--fg-default))"
      expect(stops).to start_with("#{green} 0")
      expect(stops).to match(/\A#{Regexp.escape(green)} 0(\.0+)?%/)
    end

    it "projects a large completionist axis (Crimson-Desert scale) so pink dominates" do
      # completionist = 738h → 100h projects to ~13.6%, pink fills the rest
      crimson = described_class.new(
        hours:         { main: 31, extras: 71, completionist: 738 },
        footage_hours: 0
      )
      stops = crimson.gradient_stops
      # The 100h pink stop is the red→purple mix wrapped in the T17.1 fg-mix;
      # grab the percentage that immediately follows it (color-mix
      # expressions contain commas, so we can't naively split on ", ").
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

    it "renders three pillar | ticks plus a footage ▼ bubble (T17.4)" do
      comp = described_class.new(game: game, footage_hours: 50)
      html = render_inline(comp).to_html
      # Footage uses the ScoreBar-style arrow bubble, not a | tick, so only
      # the three pillars draw a pito-ttb__tick.
      expect(html.scan("pito-ttb__tick").size).to eq(3)
      expect(html).to include("pito-ttb__footage-bubble-arrow")
    end

    it "pins the completionist tick to the last-cell midpoint (98.75%)" do
      comp = described_class.new(game: game)
      html = render_inline(comp).to_html
      expect(html).to include("left: 98.75%")
    end
  end

  # ── NEW PARTIAL-DATA SPECS (rules 1-5) ──────────────────────────────────

  describe "all three pillars present — completionist at max (rule 1/2/5)" do
    subject(:comp) { described_class.new(hours: { main: 50, extras: 100, completionist: 200 }) }

    it "completionist is the axis max (tick_axis = completionist)" do
      expect(comp.tick_axis).to eq(200)
    end

    it "completionist tick lands at the right end (98.75%)" do
      expect(comp.tick_position(200)).to eq(98.75)
    end

    it "other pillars scale proportionally" do
      # main 50/200 = 25% → cell 10 → 26.25%
      expect(comp.tick_position(50)).to eq(26.25)
      # extras 100/200 = 50% → cell 20 → 51.25%
      expect(comp.tick_position(100)).to eq(51.25)
    end

    it "gradient goes full ramp to pink (completionist present)" do
      stops = comp.gradient_stops
      expect(stops).to include("var(--accent-purple)")
    end

    it "gradient_terminal_pillar is :completionist" do
      expect(comp.gradient_terminal_pillar).to eq(:completionist)
    end
  end

  describe "completionist missing — extras is max (rule 1/2/3/5)" do
    subject(:comp) { described_class.new(hours: { main: 40, extras: 80, completionist: 0 }) }

    it "tick_axis equals extras" do
      expect(comp.tick_axis).to eq(80)
    end

    it "extras tick lands at the right end (98.75%)" do
      expect(comp.tick_position(80)).to eq(98.75)
    end

    it "main tick scales proportionally on the extras axis" do
      # main 40/80 = 50% → cell 20 → 51.25%
      expect(comp.tick_position(40)).to eq(51.25)
    end

    it "no completionist tick in tick_overlays" do
      keys = comp.tick_overlays.map { |t| t[:key] }
      expect(keys).not_to include(:completionist)
    end

    it "no completionist value label in pillar_label_data" do
      keys = comp.pillar_label_data.map { |d| d[:key] }
      expect(keys).not_to include(:completionist)
    end

    it "gradient_terminal_pillar is :extras" do
      expect(comp.gradient_terminal_pillar).to eq(:extras)
    end

    it "gradient terminal color is yellow (not pink)" do
      terminal_color = described_class::GRADIENT_TERMINAL_YELLOW
      stops = comp.gradient_stops
      expect(stops).to include(terminal_color)
      expect(stops).not_to include("var(--accent-purple)")
    end

    it "gradient ends at 100% with yellow" do
      terminal_color = described_class::GRADIENT_TERMINAL_YELLOW
      stops = comp.gradient_stops
      expect(stops).to end_with("#{terminal_color} 100%")
    end

    it "renders no completionist legend item in HTML" do
      html = render_inline(comp).to_html
      # The completionist legend tick is keyed on data-accent="completionist"
      # inside pito-ttb__legend-tick; look for the combination
      expect(html).not_to include('data-accent="completionist"')
    end

    it "renders main and extras legend items in HTML" do
      html = render_inline(comp).to_html
      expect(html).to include('data-accent="main"')
      expect(html).to include('data-accent="extras"')
    end
  end

  describe "only main present — main is max (rule 1/2/3/5)" do
    subject(:comp) { described_class.new(hours: { main: 43, extras: 0, completionist: 0 }) }

    it "tick_axis equals main" do
      expect(comp.tick_axis).to eq(43)
    end

    it "main tick lands at the right end (98.75%)" do
      expect(comp.tick_position(43)).to eq(98.75)
    end

    it "no extras or completionist ticks" do
      keys = comp.tick_overlays.map { |t| t[:key] }
      expect(keys).not_to include(:extras, :completionist)
    end

    it "only main appears in pillar_label_data" do
      keys = comp.pillar_label_data.map { |d| d[:key] }
      expect(keys).to eq([ :main ])
    end

    it "gradient_terminal_pillar is :main" do
      expect(comp.gradient_terminal_pillar).to eq(:main)
    end

    it "gradient terminal color is green (not yellow/pink)" do
      terminal_color = described_class::GRADIENT_TERMINAL_GREEN
      stops = comp.gradient_stops
      expect(stops).to end_with("#{terminal_color} 100%")
      expect(stops).not_to include("var(--accent-yellow)")
      expect(stops).not_to include("var(--accent-purple)")
    end

    it "renders only the main legend item in HTML" do
      html = render_inline(comp).to_html
      expect(html).to include('data-accent="main"')
      expect(html).not_to include('data-accent="extras"')
      expect(html).not_to include('data-accent="completionist"')
    end
  end

  describe "all pillars missing — no pillar ticks or labels (rule 1/3)" do
    subject(:comp) { described_class.new(hours: { main: 0, extras: 0, completionist: 0 }) }

    it "pillar_axis is 0" do
      expect(comp.pillar_axis).to eq(0)
    end

    it "tick_overlays contains only the footage entry (no pillar ticks)" do
      keys = comp.tick_overlays.map { |t| t[:key] }
      expect(keys).to eq([ :footage ])
    end

    it "pillar_label_data is empty" do
      expect(comp.pillar_label_data).to be_empty
    end

    it "no pillar legend items in HTML" do
      html = render_inline(comp).to_html
      expect(html).not_to include('data-accent="main"')
      expect(html).not_to include('data-accent="extras"')
      expect(html).not_to include('data-accent="completionist"')
    end
  end

  describe "footage absent — mark at left with em-dash label (rule 4)" do
    subject(:comp) { described_class.new(hours: { main: 50, extras: 100, completionist: 200 }, footage_hours: 0) }

    it "footage_label_alignment_class is at-start" do
      expect(comp.footage_label_alignment_class).to eq("ttb-label--at-start")
    end

    it "footage_value_label returns em-dash" do
      expect(comp.footage_value_label).to eq("—")
    end

    it "footage tick position is at the first cell midpoint (1.25%)" do
      expect(comp.footage_position).to eq(1.25)
    end
  end

  describe "footage > pillar max — footage becomes axis max (rule 4)" do
    # footage=300 exceeds completionist=200, so footage drives the axis
    subject(:comp) { described_class.new(hours: { main: 50, extras: 100, completionist: 200 }, footage_hours: 300) }

    it "effective_axis equals footage_hours" do
      expect(comp.effective_axis).to eq(300)
    end

    it "tick_axis equals footage_hours" do
      expect(comp.tick_axis).to eq(300)
    end

    it "footage tick lands at the right end (98.75%)" do
      expect(comp.footage_position).to eq(98.75)
    end

    it "completionist rescales to its proportional position on the footage axis" do
      # comp=200, axis=300 → 66.66% → cell 26 → 66.25%
      expect(comp.tick_position(200)).to eq(66.25)
    end

    it "max_x is based on footage (footage * 1.05)" do
      # effective_axis=300; max(300,10)*1.05=315
      expect(comp.max_x).to eq(315)
    end

    it "gradient_stops also uses the footage-based axis (color_axis_max=300)" do
      expect(comp.color_axis_max).to eq(300)
    end

    it "gradient terminal is still completionist-driven (completionist present)" do
      expect(comp.gradient_terminal_pillar).to eq(:completionist)
    end
  end
end
