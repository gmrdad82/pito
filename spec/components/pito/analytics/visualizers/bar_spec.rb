# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Visualizers::Bar, type: :component do
  COLS = Pito::Analytics::Visualizers::Base::COLS # 42
  ROWS = Pito::Analytics::Visualizers::Base::ROWS # 11

  BAR_FILL  = [ 0x28FF ].pack("U") # ⣿
  BLANK_CHR = [ 0x2800 ].pack("U") # ⠀

  def braille?(text)
    text.chars.any? { |c| c.ord.between?(0x2800, 0x28FF) }
  end

  def render_bars(bars:, caption: "bar chart caption")
    render_inline(described_class.new(bars:, caption:))
  end

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  let(:bar_red)    { { label: "Red",    pct: 90.0, color: :red,   value_label: "90.0%" } }
  let(:bar_green)  { { label: "Green",  pct: 10.0, color: :green, value_label: "10.0%" } }
  let(:bar_blue)   { { label: "Blue",   pct: 50.0, color: :blue } }
  let(:bar_purple) { { label: "Purple", pct: 33.0, color: :purple } }
  let(:bar_cyan)   { { label: "Cyan",   pct: 75.0, color: :cyan } }

  let(:one_bar)   { [ bar_red ] }
  let(:two_bars)  { [ bar_red, bar_green ] }
  let(:three_bars) { [ bar_red, bar_green, bar_blue ] }
  let(:four_bars)  { [ bar_red, bar_green, bar_blue, bar_purple ] }
  let(:five_bars)  { [ bar_red, bar_green, bar_blue, bar_purple, bar_cyan ] }

  # ── Chrome + controller ──────────────────────────────────────────────────────

  it "renders a .pito-metric.pito-metric--bar wrapper with the reveal controller" do
    node = render_bars(bars: two_bars)
    wrapper = node.at_css(".pito-metric.pito-metric--bar")
    expect(wrapper).to be_present
    expect(wrapper["data-controller"]).to eq("pito--area-chart-reveal")
  end

  it "renders a .pito-metric__chart container" do
    node = render_bars(bars: two_bars)
    expect(node.at_css(".pito-metric__chart")).to be_present
  end

  it "renders a .pito-metric__plot with --pito-rows: 11 and the reveal plot target" do
    node = render_bars(bars: two_bars)
    plot = node.at_css(".pito-metric__plot")
    expect(plot).to be_present
    expect(plot["style"]).to include("--pito-rows: 11")
    expect(plot["data-pito--area-chart-reveal-target"]).to eq("plot")
  end

  # ── Exactly 11 brow rows always ──────────────────────────────────────────────

  [ :one_bar, :two_bars, :three_bars, :four_bars, :five_bars ].each_with_index do |bars_fixture, idx|
    it "renders exactly 11 .pito-metric__brow rows for #{idx + 1} bar(s)" do
      bars = send(bars_fixture) # rubocop:disable RSpec/InstanceVariable
      node = render_bars(bars:)
      expect(node.css(".pito-metric__brow").size).to eq(11)
    end
  end

  it "assigns area-chart-reveal row targets to every .pito-metric__brow" do
    node = render_bars(bars: two_bars)
    rows = node.css(".pito-metric__brow")
    expect(rows.map { |r| r["data-pito--area-chart-reveal-target"] }.uniq).to eq([ "row" ])
  end

  it "sets --i as consecutive 0..10 across the 11 rows" do
    node = render_bars(bars: two_bars)
    rows = node.css(".pito-metric__brow")
    expect(rows.map { |r| r["style"][/--i:\s*(\d+)/, 1].to_i }).to eq((0..10).to_a)
  end

  # ── Total char count per row = COLS ──────────────────────────────────────────

  it "renders each bar row as exactly #{COLS} braille chars" do
    node = render_bars(bars: two_bars)
    node.css(".pito-metric__brow").each do |row|
      expect(row.text.length).to eq(COLS)
    end
  end

  it "renders each bar row as exactly #{COLS} chars for 5 bars" do
    node = render_bars(bars: five_bars)
    node.css(".pito-metric__brow").each do |row|
      expect(row.text.length).to eq(COLS)
    end
  end

  # ── Group vertical centring ───────────────────────────────────────────────────

  it "centres 1 bar with 4 blank rows above and 5 below" do
    node  = render_bars(bars: one_bar)
    rows  = node.css(".pito-metric__brow")
    texts = rows.map(&:text)
    # rows 0-3 blank, rows 4-5 bar, rows 6-10 blank
    expect(texts[0..3].all? { |t| t == BLANK_CHR * COLS }).to be(true)
    expect(texts[4..5].none? { |t| t == BLANK_CHR * COLS }).to be(true)
    expect(texts[6..10].all? { |t| t == BLANK_CHR * COLS }).to be(true)
  end

  it "centres 2 bars with 3 blank rows above and 3 below (5 content rows)" do
    node  = render_bars(bars: two_bars)
    rows  = node.css(".pito-metric__brow")
    texts = rows.map(&:text)
    # rows 0-2 blank, rows 3-7 content (2+gap+2), rows 8-10 blank
    expect(texts[0..2].all? { |t| t == BLANK_CHR * COLS }).to be(true)
    expect(texts[8..10].all? { |t| t == BLANK_CHR * COLS }).to be(true)
  end

  it "places no blank pad rows for 4 bars (exactly fills 11 rows with gaps)" do
    node  = render_bars(bars: four_bars)
    rows  = node.css(".pito-metric__brow")
    texts = rows.map(&:text)
    # No blank-pad rows — all 11 are either bar or gap rows
    blank_pads = texts.each_with_index.count { |t, _i| t == BLANK_CHR * COLS }
    # 3 gap rows between 4 bars, no top/bottom pad
    expect(blank_pads).to eq(3)
  end

  it "has 1 blank row at the bottom for 5 bars (10 bar rows, no gaps, 1 pad below)" do
    node  = render_bars(bars: five_bars)
    rows  = node.css(".pito-metric__brow")
    texts = rows.map(&:text)
    # No gap rows; 10 bar rows fill rows 0-9; 1 blank pad at bottom
    expect(texts[0..9].none? { |t| t == BLANK_CHR * COLS }).to be(true)
    expect(texts[10]).to eq(BLANK_CHR * COLS)
  end

  # ── Fill span cell count ∝ pct ────────────────────────────────────────────────

  it "fills ~90% of cells for a 90% bar (row char count proportional)" do
    node = render_bars(bars: [ bar_red ])
    # Find the non-blank brow rows
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.text == BLANK_CHR * COLS }
    fill_span = bar_rows.first.at_css(".pito-bar-fill:not(.is-outline)")
    expected_filled = [ (90.0 / 100.0 * COLS).round, 1 ].max
    expect(fill_span.text.length).to eq(expected_filled)
  end

  it "shows ≥1 filled cell for a tiny positive pct (min-1-cell guarantee)" do
    tiny_bar = { label: "Tiny", pct: 0.5, color: :red }
    node     = render_bars(bars: [ tiny_bar ])
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.text == BLANK_CHR * COLS }
    fill_span = bar_rows.first.at_css(".pito-bar-fill:not(.is-outline)")
    expect(fill_span.text.length).to be >= 1
  end

  it "shows 0 filled cells for a 0% bar (empty fill span)" do
    zero_bar = { label: "Zero", pct: 0.0, color: :green }
    node     = render_bars(bars: [ zero_bar ])
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.text == BLANK_CHR * COLS }
    fill_span = bar_rows.first.at_css(".pito-bar-fill:not(.is-outline)")
    expect(fill_span.text.length).to eq(0)
  end

  it "clamps pct above 100 to 100 and caps fill at COLS-1 (no canvas overflow)" do
    over_bar = { label: "Over", pct: 150.0, color: :cyan }
    node     = render_bars(bars: [ over_bar ])
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.text == BLANK_CHR * COLS }
    fill_span      = bar_rows.first.at_css(".pito-bar-fill:not(.is-outline)")
    remainder_span = bar_rows.first.css(".pito-bar-fill.is-outline").last
    expect(fill_span.text.length).to eq(COLS - 1)
    expect(remainder_span.text.length).to be >= 1
  end

  it "caps a 100% bar at COLS-1 filled cells, leaving ≥1 cell of headroom" do
    full_bar = { label: "Full", pct: 100.0, color: :blue }
    node     = render_bars(bars: [ full_bar ])
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.text == BLANK_CHR * COLS }
    fill_span      = bar_rows.first.at_css(".pito-bar-fill:not(.is-outline)")
    remainder_span = bar_rows.first.css(".pito-bar-fill.is-outline").last
    expect(fill_span.text.length).to eq(COLS - 1)
    expect(remainder_span.text.length).to be >= 1
  end

  # ── Remainder span ────────────────────────────────────────────────────────────

  it "marks the remainder span with .is-outline" do
    node     = render_bars(bars: [ bar_red ])
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.text == BLANK_CHR * COLS }
    expect(bar_rows.first.at_css(".pito-bar-fill.is-outline")).to be_present
  end

  it "ensures the bar segments (offset lead + fill + remainder) total COLS chars per row" do
    node     = render_bars(bars: two_bars)
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.css(".pito-bar-fill").empty? }
    bar_rows.each do |row|
      total = row.css(".pito-bar-fill").sum { |s| s.text.length }
      expect(total).to eq(COLS)
    end
  end

  it "offsets each bar's coloured segment to where the previous bar's slice ended" do
    # two_bars sums to 100; the 2nd bar's coloured (non-outline) segment must start
    # after a non-empty dim LEAD = the 1st bar's width.
    node     = render_bars(bars: two_bars)
    bar_rows = node.css(".pito-metric__brow").reject { |r| r.css(".pito-bar-fill").empty? }
    second   = bar_rows[2] || bar_rows[1] # row 1 of the 2nd bar (after the 1st bar's 2 rows)
    leads    = second.css(".pito-bar-fill.is-outline").map { |s| s.text.length }
    expect(leads.first).to be > 0 # non-zero dim lead before the 2nd slice
  end

  # ── --bar-color set on fill spans ─────────────────────────────────────────────

  it "sets --bar-color on the fill spans for each bar" do
    node   = render_bars(bars: two_bars)
    colors = node.css(".pito-bar-fill").map { |s| s["style"] }.join(" ")
    expect(colors).to include("--bar-color: var(--accent-red)")
    expect(colors).to include("--bar-color: var(--accent-green)")
  end

  it "uses --brand-pito for the :blue color token" do
    node   = render_bars(bars: [ bar_blue ])
    colors = node.css(".pito-bar-fill").map { |s| s["style"] }.join(" ")
    expect(colors).to include("--bar-color: var(--brand-pito)")
  end

  # ── Legend ────────────────────────────────────────────────────────────────────

  it "renders one .pito-metric__blegend-item per bar" do
    node  = render_bars(bars: three_bars)
    items = node.css(".pito-metric__blegend-item")
    expect(items.size).to eq(3)
  end

  it "includes the label and value_label in each legend item" do
    node  = render_bars(bars: two_bars)
    items = node.css(".pito-metric__blegend-item")
    expect(items[0].text).to include("Red").and include("90.0%")
    expect(items[1].text).to include("Green").and include("10.0%")
  end

  it "defaults value_label to XX.X% when not supplied" do
    node = render_bars(bars: [ { label: "Foo", pct: 42.5, color: :blue } ])
    expect(node.at_css(".pito-metric__blegend-item").text).to include("42.5%")
  end

  it "renders the coloured ● swatch inside each legend item" do
    node  = render_bars(bars: two_bars)
    items = node.css(".pito-metric__blegend-item")
    items.each { |item| expect(item.text).to include("●") }
  end

  # ── Caption ───────────────────────────────────────────────────────────────────

  it "renders the caption in .pito-metric__caption.text-fg-dim" do
    node = render_bars(bars: one_bar, caption: "test caption text")
    caption = node.at_css(".pito-metric__caption")
    expect(caption).to be_present
    expect(caption["class"]).to include("text-fg-dim")
    expect(caption.text).to include("test caption text")
  end

  it "does NOT render an empty .pito-metric__caption <p> when caption is blank" do
    node = render_bars(bars: one_bar, caption: "")
    expect(node.at_css(".pito-metric__caption")).to be_nil
  end

  # ── Background grid ───────────────────────────────────────────────────────────

  it "renders the dotted-paper bg with 11 .pito-metric__bg-row spans" do
    node = render_bars(bars: one_bar)
    bg   = node.at_css(".pito-metric__bg")
    expect(bg).to be_present
    expect(bg.css(".pito-metric__bg-row").size).to eq(11)
    expect(braille?(bg.text)).to be(true)
  end

  it "floors the last bg row with the baseline dot (⣀)" do
    node    = render_bars(bars: one_bar)
    bg_rows = node.css(".pito-metric__bg-row")
    expect(bg_rows.last.text).to include(Pito::Analytics::Visualizers::Base::BASELINE_DOT)
  end

  # ── Shimmer offset class ──────────────────────────────────────────────────────

  it "applies a pito-shimmer-dN class to every fill span in the chart" do
    node = render_bars(bars: two_bars)
    fill_spans = node.css(".pito-bar-fill")
    classes = fill_spans.map { |s| s["class"][/pito-shimmer-d\d+/] }
    expect(classes).to all(match(/\Apito-shimmer-d\d+\z/))
  end

  it "uses the same shimmer offset class across all fill spans (whole group in phase)" do
    node    = render_bars(bars: three_bars)
    classes = node.css(".pito-bar-fill").map { |s| s["class"][/pito-shimmer-d\d+/] }.uniq
    expect(classes.size).to eq(1)
  end
end
