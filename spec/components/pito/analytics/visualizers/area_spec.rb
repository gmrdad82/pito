# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Visualizers::Area do
  def render_chart(metric: :views, series:, target_daily: 5.0, caption: "Views: 42.")
    render_inline(described_class.new(metric:, series:, target_daily:, caption:))
  end

  def braille?(text)
    text.chars.any? { |c| c.ord.between?(0x2800, 0x28FF) }
  end

  # ── Reveal controller ────────────────────────────────────────────────────────

  it "mounts the area-chart-reveal controller (not views-reveal)" do
    node    = render_chart(series: [ 1, 4, 9 ])
    wrapper = node.css(".pito-metric--area-chart").first
    expect(wrapper).to be_present
    expect(wrapper["data-controller"]).to eq("pito--area-chart-reveal")
  end

  # ── Braille plot ─────────────────────────────────────────────────────────────

  it "renders the braille plot (area-chart-reveal target) carrying braille glyphs" do
    node = render_chart(series: [ 2, 6, 4 ])
    plot = node.css(".pito-metric__plot").first
    expect(plot["data-pito--area-chart-reveal-target"]).to eq("plot")
    expect(braille?(plot.text)).to be(true)
  end

  it "renders one braille ROW span per cell row, each an area-chart-reveal target with --i" do
    node = render_chart(series: [ 3, 7, 5 ])
    rows = node.css(".pito-metric__row")
    expect(rows.size).to eq(described_class::ROWS)
    expect(rows.map { |r| r["data-pito--area-chart-reveal-target"] }.uniq).to eq([ "row" ])
    expect(rows.each_with_index.all? { |r, i| r["style"].include?("--i: #{i}") }).to be(true)
    expect(rows.all? { |r| braille?(r.text) }).to be(true)
  end

  # ── Shimmer offset ───────────────────────────────────────────────────────────

  it "applies ONE shared shimmer-offset bucket to every row (whole chart in phase)" do
    rows = render_chart(series: [ 4, 8, 2 ]).css(".pito-metric__row")
    buckets = rows.map { |r| r["class"][/pito-shimmer-d\d+/] }
    expect(buckets.uniq.size).to eq(1)
    expect(buckets.first).to match(/\Apito-shimmer-d\d+\z/)
  end

  it "produces DISTINCT shimmer offsets for different metrics with the same series" do
    series = [ 1, 2, 3 ]
    views_chart  = described_class.new(metric: :views,         series:, target_daily: 5.0, caption: "x")
    wh_chart     = described_class.new(metric: :watched_hours, series:, target_daily: 5.0, caption: "x")
    subs_chart   = described_class.new(metric: :subs,          series:, target_daily: 5.0, caption: "x")
    # The metric prefix ensures they differ even when series and target are identical.
    offsets = [ views_chart.shimmer_offset_class, wh_chart.shimmer_offset_class, subs_chart.shimmer_offset_class ]
    expect(offsets).to all(match(/\Apito-shimmer-d\d+\z/))
    # At least two of the three differ (all three could theoretically collide in a
    # 20-bucket hash, but views/wh/subs prefix strings always hash differently).
    expect(offsets.uniq.size).to be >= 2
  end

  it "seeds the shimmer bucket per chart so different series can differ within a metric" do
    a = described_class.new(metric: :views, series: [ 1, 2, 3 ], target_daily: 5.0, caption: "x")
    b = described_class.new(metric: :views, series: [ 9, 1, 7, 3 ], target_daily: 5.0, caption: "x")
    expect(a.shimmer_offset_class).to match(/\Apito-shimmer-d\d+\z/)
    expect(b.shimmer_offset_class).to match(/\Apito-shimmer-d\d+\z/)
  end

  # ── Gradient vars ─────────────────────────────────────────────────────────────

  it "carries the data-driven green-anchor + row-count CSS vars on the plot" do
    node = render_chart(series: [ 10, 10 ], target_daily: 1.0)
    plot = node.css(".pito-metric__plot").first
    # ceiling = max(peak 10, target 1, 1) = 10 → anchor = 1/10 = 10%
    expect(plot["style"]).to include("--pito-green-anchor: 10%")
    expect(plot["style"]).to include("--pito-rows: #{described_class::ROWS}")
  end

  it "clamps the green anchor to 100% when the scope underperforms its target" do
    node = render_chart(series: [ 1, 1 ], target_daily: 50.0)
    plot = node.css(".pito-metric__plot").first
    # ceiling = max(peak 1, target 50) = 50 → anchor = 50/50 = 100%
    expect(plot["style"]).to include("--pito-green-anchor: 100%")
  end

  it "anchors an EMPTY chart with a FRACTIONAL target at 100% (red baseline, not green-heavy)" do
    # Regression (owner 2026-07-01): watched_hours/subs on a small channel have a
    # daily target < 1. The plot-scale 1.0 ceiling floor used to drag the anchor to
    # target/1.0 (a few %), painting an empty chart green from the baseline. The
    # anchor now uses max(peak, target) (no floor) → target/target = 100% → red base.
    wh = render_chart(metric: :watched_hours, series: [], target_daily: 0.357)
    expect(wh.css(".pito-metric__plot").first["style"]).to include("--pito-green-anchor: 100%")

    subs = render_chart(metric: :subs, series: [], target_daily: 0.071)
    expect(subs.css(".pito-metric__plot").first["style"]).to include("--pito-green-anchor: 100%")
  end

  # ── Tick values ───────────────────────────────────────────────────────────────

  it "renders discrete y-VALUE ticks inside-left at their data height (no rotation)" do
    node = render_chart(series: [ 100, 50, 0 ], target_daily: 1.0)
    ticks = node.css(".pito-metric__yticks .pito-metric__ytick")
    expect(ticks.size).to eq(3)
    # ceiling = 100 → top tick at top:0%
    expect(ticks.first["style"]).to include("top: 0")
    # compact-formatted for large numbers
    big = render_chart(series: [ 12_000, 6_000 ], target_daily: 1.0)
    expect(big.css(".pito-metric__ytick").first.text).to eq("12K")
  end

  it "renders discrete x-VALUE ticks below the plot" do
    node = render_chart(series: (1..30).to_a)
    xticks = node.css(".pito-metric__xticks span")
    expect(xticks.size).to eq(5)
    expect(xticks.first.text).to eq("1")
    expect(xticks.last.text).to eq("30")
  end

  it "does NOT render axis lines or names (locked: ticks only)" do
    node = render_chart(series: [ 5 ])
    expect(node.css(".pito-metric__axis-y")).to be_empty
    expect(node.css(".pito-metric__axis-x")).to be_empty
  end

  # ── Caption ───────────────────────────────────────────────────────────────────

  it "renders the caption (theme-dim) below the chart" do
    node = render_chart(series: [ 3 ], caption: "Views: the insignificant 3.")
    cap  = node.css(".pito-metric__caption").first
    expect(cap.text).to eq("Views: the insignificant 3.")
    expect(cap["class"]).to include("text-fg-dim")
  end

  it "does NOT render an empty .pito-metric__caption <p> when caption is blank" do
    node = render_chart(series: [ 3 ], caption: "")
    expect(node.at_css(".pito-metric__caption")).to be_nil
  end

  it "renders a pre-rendered html caption RAW (subject + reference tokens survive)" do
    caption = %(<span class="pito-subject-shimmer">Views</span>: ) +
              %(<span class="pito-reference-shimmer">842K</span>.)
    cap = render_chart(series: [ 5 ], caption:).css(".pito-metric__caption").first
    expect(cap.css("span.pito-subject-shimmer").text).to eq("Views")
    expect(cap.css("span.pito-reference-shimmer").text).to eq("842K")
  end

  it "ticks ride the theme dim token (theme-dependent)" do
    node = render_chart(series: [ 4 ])
    expect(node.css(".pito-metric__yticks").first["class"]).to include("text-fg-dim")
    expect(node.css(".pito-metric__xticks").first["class"]).to include("text-fg-dim")
  end

  # ── All 3 metrics render without errors ───────────────────────────────────────

  it "renders watched_hours metric correctly" do
    node = render_chart(metric: :watched_hours, series: [ 2.5, 3.1, 1.8 ], target_daily: 0.5, caption: "Watch hours: 7h.")
    wrapper = node.css(".pito-metric--area-chart").first
    expect(wrapper).to be_present
    expect(wrapper["data-controller"]).to eq("pito--area-chart-reveal")
    expect(braille?(node.css(".pito-metric__plot").first.text)).to be(true)
  end

  it "renders subs metric correctly" do
    node = render_chart(metric: :subs, series: [ 5, -2, 8 ], target_daily: 1.4, caption: "Subs: +11.")
    wrapper = node.css(".pito-metric--area-chart").first
    expect(wrapper).to be_present
    expect(braille?(node.css(".pito-metric__plot").first.text)).to be(true)
  end

  # ── trend: / reference_token: params ─────────────────────────────────────────

  it "stores trend: false and exposes it via #trend" do
    chart = described_class.new(metric: :avg_view_duration, series: [ 90.0, 120.0 ], target_daily: 120.0, caption: "x", trend: false)
    expect(chart.trend).to be(false)
  end

  it "defaults trend: to true" do
    chart = described_class.new(metric: :views, series: [ 1, 2 ], target_daily: 5.0, caption: "x")
    expect(chart.trend).to be(true)
  end

  it "stores reference_token: and exposes it via #reference_token" do
    chart = described_class.new(metric: :avg_viewed_pct, series: [ 90.0, 80.0 ], target_daily: 50.0, caption: "x", reference_token: "lifetime")
    expect(chart.reference_token).to eq("lifetime")
  end

  it "defaults reference_token: to nil" do
    chart = described_class.new(metric: :views, series: [ 1 ], target_daily: 5.0, caption: "x")
    expect(chart.reference_token).to be_nil
  end

  # ── avg_view_duration formatting ─────────────────────────────────────────────

  it "renders M:SS y-ticks for avg_view_duration" do
    # ceiling = max(120.0, 120.0) = 120s → top tick "2:00"
    node   = render_chart(metric: :avg_view_duration, series: [ 90.0, 120.0 ], target_daily: 120.0,
                          caption: "Avg view duration: 2:00.")
    ticks  = node.css(".pito-metric__ytick")
    labels = ticks.map(&:text)
    # Ceiling 120 → "2:00"; 79.2 → "1:19"; 39.6 → "0:40" (approx)
    expect(labels.first).to eq("2:00")
    expect(labels.last).to match(/\A\d+:\d{2}\z/)
  end

  it "renders avg_view_duration area chart without errors (trend: false accepted)" do
    node = render_chart(metric: :avg_view_duration, series: [ 90.0, 120.0, 110.0 ],
                        target_daily: 120.0, caption: "Avg view duration: 1:53.")
    expect(node.css(".pito-metric--area-chart").first).to be_present
    expect(braille?(node.css(".pito-metric__plot").first.text)).to be(true)
  end

  # ── avg_viewed_pct formatting ─────────────────────────────────────────────────

  it "renders XX.XX% y-ticks for avg_viewed_pct" do
    node   = render_chart(metric: :avg_viewed_pct, series: [ 90.0, 80.0, 50.0 ],
                          target_daily: 50.0, caption: "Avg retention: 60.0%.")
    ticks  = node.css(".pito-metric__ytick")
    labels = ticks.map(&:text)
    expect(labels).to all(match(/\A\d+\.\d\d%\z/))
    expect(labels.first).to eq("90.00%")
  end

  it "renders percentage x-ticks (0%→100%) for avg_viewed_pct" do
    node   = render_chart(metric: :avg_viewed_pct,
                          series: (1..20).map { |i| 100.0 - (i * 3.0) },
                          target_daily: 50.0, caption: "x")
    xticks = node.css(".pito-metric__xticks span")
    labels = xticks.map(&:text)
    expect(labels).to eq([ "0%", "25%", "50%", "75%", "100%" ])
  end

  it "renders day-index x-ticks (not %) for :views when no dates provided" do
    node   = render_chart(metric: :views, series: (1..30).to_a, target_daily: 5.0, caption: "x")
    xticks = node.css(".pito-metric__xticks span")
    expect(xticks.map(&:text)).to all(match(/\A\d+\z/))
  end

  # ── Date-labelled x-ticks (ACL6) ─────────────────────────────────────────────

  it "renders date-labelled x-ticks in 'day month' format when dates are current-year" do
    current_year = Date.current.year
    # 7 daily dates in the current year
    start = Date.new(current_year, 2, 1)
    dates = (0..6).map { |i| (start + i).iso8601 }
    node   = render_inline(described_class.new(
      metric: :views, series: (1..7).to_a, target_daily: 5.0,
      caption: "x", dates: dates
    ))
    xticks = node.css(".pito-metric__xticks span")
    # At least the first tick should look like "1 Feb" (day + abbreviated month)
    expect(xticks.first.text).to match(/\A\d{1,2} [A-Z][a-z]{2}\z/)
    # None should be a raw day-index
    expect(xticks.map(&:text)).not_to include("1")
  end

  it "renders date-labelled x-ticks in 'Month YYYY' format for prior-year dates" do
    prior_year = Date.current.year - 1
    start = Date.new(prior_year, 6, 1)
    dates = (0..29).map { |i| (start + i).iso8601 }
    node  = render_inline(described_class.new(
      metric: :views, series: (1..30).to_a, target_daily: 5.0,
      caption: "x", dates: dates
    ))
    xticks = node.css(".pito-metric__xticks span")
    # All ticks should be "Month YYYY" since the dates are in a prior year
    expect(xticks.map(&:text)).to all(match(/\A[A-Z][a-z]+ \d{4}\z/))
  end

  it "returns the retention 0%→100% labels regardless of dates" do
    dates = (0..9).map { |i| (Date.current - i).iso8601 }
    chart = described_class.new(
      metric: :avg_viewed_pct, series: (1..10).to_a,
      target_daily: 50.0, caption: "x", dates: dates
    )
    expect(chart.x_ticks).to eq([ "0%", "25%", "50%", "75%", "100%" ])
  end

  it "falls back to a single date label for a 1-point series with dates" do
    dates = [ Date.current.iso8601 ]
    chart = described_class.new(
      metric: :views, series: [ 42 ], target_daily: 5.0, caption: "x", dates: dates
    )
    expect(chart.x_ticks.size).to eq(1)
    expect(chart.x_ticks.first).to match(/\A\d{1,2} [A-Z][a-z]{2}\z/)
  end
end
