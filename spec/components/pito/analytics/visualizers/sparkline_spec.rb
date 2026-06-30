# frozen_string_literal: true

require "rails_helper"

# The dedicated 2-row braille sparkline used above a glance scalar. (Extracted out
# of Slots::Compact so the sparkline is a first-class, reusable component — no
# inline chart code in the host.)
RSpec.describe Pito::Analytics::Visualizers::Sparkline, type: :component do
  def braille?(text) = text.chars.any? { |c| c.ord.between?(0x2800, 0x28FF) }

  let(:cols) { Pito::Analytics::Visualizers::Base::COLS }

  subject(:node) { render_inline(described_class.new(series: [ 10, 30, 20, 50, 40 ])) }

  it "subclasses BaseComponent (the 45-col braille canvas)" do
    expect(described_class.ancestors).to include(Pito::Analytics::Visualizers::Base)
    expect(described_class.new(series: [ 1, 2 ]).cols).to eq(45)
  end

  it "renders a .pito-metric--sparkline wrapper with the area-chart-reveal controller" do
    wrapper = node.at_css(".pito-metric.pito-metric--sparkline")
    expect(wrapper).to be_present
    expect(wrapper["data-controller"]).to eq("pito--area-chart-reveal")
  end

  it "renders exactly ROWS (2) braille rows" do
    rows = node.css(".pito-metric__row")
    expect(rows.size).to eq(described_class::ROWS)
    expect(described_class::ROWS).to eq(2)
    expect(rows.all? { |r| braille?(r.text) }).to be(true)
  end

  it "renders each row as a COLS (45) char braille string" do
    node.css(".pito-metric__row").each { |r| expect(r.text.length).to eq(cols) }
  end

  it "assigns reveal row targets + a per-row --i" do
    rows = node.css(".pito-metric__row")
    expect(rows.map { |r| r["data-pito--area-chart-reveal-target"] }.uniq).to eq([ "row" ])
    expect(rows[0]["style"]).to include("--i: 0")
    expect(rows[1]["style"]).to include("--i: 1")
  end

  it "applies one shared shimmer-offset class across the rows" do
    buckets = node.css(".pito-metric__row").map { |r| r["class"][/pito-shimmer-d\d+/] }
    expect(buckets.uniq.size).to eq(1)
  end

  it "renders the dotted-paper bg with a floored baseline row" do
    expect(node.at_css(".pito-metric__bg")).to be_present
    expect(node.css(".pito-metric__bg-row").last.text).to include(Pito::Analytics::Visualizers::Base::BASELINE_DOT)
  end

  it "floors a minimal baseline for an all-zero series (always an x-axis line)" do
    zero = render_inline(described_class.new(series: [ 0, 0, 0 ]))
    expect(zero.css(".pito-metric__row").last.text).to include(Pito::Analytics::Visualizers::Base::BASELINE_DOT)
  end

  it "renders a visible bump above baseline for a tiny non-zero integer value" do
    # 1 view against a high series_max must render a bump, not a flat baseline.
    tiny = render_inline(described_class.new(series: [ 1 ], series_max: 1000))
    zero = render_inline(described_class.new(series: [ 0 ]))
    expect(tiny.css(".pito-metric__row").last.text).not_to eq(zero.css(".pito-metric__row").last.text)
  end

  it "renders a bump for a fractional non-zero value (0.1 must not round to zero)" do
    # Without the fix, 0.1.round → 0 collapses to the same flat line as all-zero.
    frac = render_inline(described_class.new(series: [ 0.1 ]))
    zero = render_inline(described_class.new(series: [ 0 ]))
    expect(frac.css(".pito-metric__row").last.text).not_to eq(zero.css(".pito-metric__row").last.text)
  end

  it "renders NO ticks / legend / caption (sparkline chrome only)" do
    expect(node.at_css(".pito-metric__ytick")).to be_nil
    expect(node.at_css(".pito-metric__xticks")).to be_nil
    expect(node.at_css(".pito-metric__caption")).to be_nil
  end
end
