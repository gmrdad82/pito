# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Metric::ViewsComponent do
  def render_views(series:, target_daily: 5.0, caption: "Views: 42.")
    render_inline(described_class.new(series:, target_daily:, caption:))
  end

  def braille?(text)
    text.chars.any? { |c| c.ord.between?(0x2800, 0x28FF) }
  end

  it "renders the views metric wrapper mounting the reveal controller" do
    node = render_views(series: [ 1, 4, 9 ])
    wrapper = node.css(".pito-metric--views").first
    expect(wrapper).to be_present
    expect(wrapper["data-controller"]).to eq("pito--views-reveal")
  end

  it "renders the braille plot (reveal target) carrying braille glyphs" do
    node = render_views(series: [ 2, 6, 4 ])
    plot = node.css(".pito-metric__plot").first
    expect(plot["data-pito--views-reveal-target"]).to eq("plot")
    expect(braille?(plot.text)).to be(true)
  end

  it "renders one braille ROW span per cell row, each a reveal target with --i" do
    node = render_views(series: [ 3, 7, 5 ])
    rows = node.css(".pito-metric__row")
    expect(rows.size).to eq(described_class::ROWS)
    expect(rows.map { |r| r["data-pito--views-reveal-target"] }.uniq).to eq([ "row" ])
    expect(rows.each_with_index.all? { |r, i| r["style"].include?("--i: #{i}") }).to be(true)
    expect(rows.all? { |r| braille?(r.text) }).to be(true)
  end

  it "applies ONE shared shimmer-offset bucket to every row (whole chart in phase)" do
    rows = render_views(series: [ 4, 8, 2 ]).css(".pito-metric__row")
    buckets = rows.map { |r| r["class"][/pito-shimmer-d\d+/] }
    expect(buckets.uniq.size).to eq(1)
    expect(buckets.first).to match(/\Apito-shimmer-d\d+\z/)
  end

  it "seeds the shimmer bucket per chart so different series can differ" do
    a = described_class.new(series: [ 1, 2, 3 ], target_daily: 5.0, caption: "x")
    b = described_class.new(series: [ 9, 1, 7, 3 ], target_daily: 5.0, caption: "x")
    # Deterministic per series (CRC32) — assert each is stable + well-formed.
    expect(a.shimmer_offset_class).to match(/\Apito-shimmer-d\d+\z/)
    expect(b.shimmer_offset_class).to match(/\Apito-shimmer-d\d+\z/)
  end

  it "carries the data-driven green-anchor + row-count CSS vars on the plot" do
    node = render_views(series: [ 10, 10 ], target_daily: 1.0)
    plot = node.css(".pito-metric__plot").first
    # ceiling = max(peak 10, target 1) = 10 → anchor = 1/10 = 10%
    expect(plot["style"]).to include("--pito-green-anchor: 10%")
    expect(plot["style"]).to include("--pito-rows: #{described_class::ROWS}")
  end

  it "clamps the green anchor to 100% when the scope underperforms its target" do
    node = render_views(series: [ 1, 1 ], target_daily: 50.0)
    plot = node.css(".pito-metric__plot").first
    # ceiling = max(peak 1, target 50) = 50 → anchor = 50/50 = 100%
    expect(plot["style"]).to include("--pito-green-anchor: 100%")
  end

  it "renders discrete y-VALUE ticks inside-left at their data height (no rotation)" do
    node = render_views(series: [ 100, 50, 0 ], target_daily: 1.0)
    ticks = node.css(".pito-metric__yticks .pito-metric__ytick")
    expect(ticks.size).to eq(3)
    # ceiling = 100 → top tick = "100" at top:0%; compact-formatted.
    expect(ticks.first.text).to eq("100")
    expect(ticks.first["style"]).to include("top: 0")
    # values are compact (K) for large numbers
    big = render_views(series: [ 12_000, 6_000 ], target_daily: 1.0)
    expect(big.css(".pito-metric__ytick").first.text).to eq("12K")
  end

  it "renders discrete x-VALUE ticks below the plot" do
    node = render_views(series: (1..30).to_a)
    xticks = node.css(".pito-metric__xticks span")
    expect(xticks.size).to eq(5)
    expect(xticks.first.text).to eq("1")
    expect(xticks.last.text).to eq("30")
  end

  it "does NOT render axis lines or names (locked: ticks only)" do
    node = render_views(series: [ 5 ])
    expect(node.css(".pito-metric__axis-y")).to be_empty
    expect(node.css(".pito-metric__axis-x")).to be_empty
  end

  it "renders the caption (theme-dim) below the chart" do
    node = render_views(series: [ 3 ], caption: "Views: the insignificant 3.")
    cap  = node.css(".pito-metric__caption").first
    expect(cap.text).to eq("Views: the insignificant 3.")
    expect(cap["class"]).to include("text-fg-dim")
  end

  it "renders a pre-rendered html caption RAW (subject + reference tokens survive)" do
    caption = %(<span class="pito-subject-shimmer">Views</span>: ) +
              %(<span class="pito-token-shimmer">842K</span>.)
    cap = render_views(series: [ 5 ], caption: caption).css(".pito-metric__caption").first
    expect(cap.css("span.pito-subject-shimmer").text).to eq("Views")
    expect(cap.css("span.pito-token-shimmer").text).to eq("842K")
  end

  it "ticks ride the theme dim token (theme-dependent)" do
    node = render_views(series: [ 4 ])
    expect(node.css(".pito-metric__yticks").first["class"]).to include("text-fg-dim")
    expect(node.css(".pito-metric__xticks").first["class"]).to include("text-fg-dim")
  end
end
