# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Visualizers::Heatmap, type: :component do
  let(:values) { [ 10.0, 20.0, 5.0, 30.0, 25.0, 40.0, 15.0 ] } # Mon..Sun; Sat=max, Wed=min
  subject(:node) { render_inline(described_class.new(values:, caption: "cap")) }

  it "renders exactly 7 bars (one per weekday)" do
    expect(node.css(".pito-heatmap__bar").size).to eq(7)
  end

  it "renders the Mo..Su x-axis labels" do
    labels = node.css(".pito-heatmap__xticks span").map(&:text)
    expect(labels).to eq(%w[Mo Tu We Th Fr Sa Su])
  end

  it "sets --pito-heat per bar, normalised 0 (min) .. 1 (max)" do
    heats = node.css(".pito-heatmap__bar").map { |b| b["style"][/--pito-heat: ([0-9.]+)/, 1].to_f }
    expect(heats[5]).to eq(1.0) # Saturday = max → 1.0 (green)
    expect(heats[2]).to eq(0.0) # Wednesday = min → 0.0 (red)
    expect(heats.min).to eq(0.0)
    expect(heats.max).to eq(1.0)
  end

  it "maps a flat week to a neutral 0.5 (no false winner/loser)" do
    flat = render_inline(described_class.new(values: Array.new(7, 12.0), caption: ""))
    heats = flat.css(".pito-heatmap__bar").map { |b| b["style"][/--pito-heat: ([0-9.]+)/, 1].to_f }
    expect(heats).to all(eq(0.5))
  end

  it "each bar is a full-height stack of solid braille blocks" do
    block = [ 0x28FF ].pack("U")
    bar   = node.css(".pito-heatmap__bar").first
    # rows joined by newline → ROWS lines of solid blocks
    expect(bar.text.split("\n").size).to eq(Pito::Analytics::Visualizers::Base::ROWS)
    expect(bar.text).to include(block)
  end

  it "renders the dotted-paper bg layer + the caption" do
    expect(node.at_css(".pito-metric__bg")).to be_present
    expect(node.text).to include("cap")
  end

  it "carries the area-chart reveal targets so the bars animate on connect" do
    expect(node.at_css("[data-controller='pito--area-chart-reveal']")).to be_present
    expect(node.css("[data-pito--area-chart-reveal-target='row']").size).to eq(7)
  end

  it "wires ONE continuous shimmer across all bars (full plot width + cumulative per-bar offsets)" do
    # The shimmer band spans the whole plot (--pito-plot-w) and each bar is shifted
    # by its cumulative width so the 135° sweep reads as a single diagonal, not a
    # per-bar sweep (owner 2026-07-01).
    plot = node.at_css(".pito-heatmap__bars")
    expect(plot["style"]).to include("--pito-plot-w: 42ch")

    offsets = node.css(".pito-heatmap__bar").map { |b| b["style"][/--pito-bar-offset: (\d+)ch/, 1].to_i }
    expect(offsets.first).to eq(0)
    expect(offsets).to eq(offsets.sort)                 # strictly non-decreasing (cumulative)
    expect(offsets.last).to be < Pito::Analytics::Visualizers::Base::COLS # last bar starts inside the plot
    # all bars share the same shimmer-delay bucket so they sweep as one
    buckets = node.css(".pito-heatmap__bar").map { |b| b["class"][/pito-shimmer-d\d+/] }
    expect(buckets.uniq.size).to eq(1)
  end

  describe "generic N-column geometry (the weekday form is just the preset)" do
    let(:cols) { Pito::Analytics::Visualizers::Base::COLS }

    it "renders N bars with matching labels, each wider than a weekday bar" do
      three = render_inline(described_class.new(values: [ 1, 2, 3 ], caption: "", labels: %w[q1 q2 q3]))
      bars = three.css(".pito-heatmap__bar")
      expect(bars.size).to eq(3)
      # COLS split 3 ways: every bar 14 cells wide vs the preset's 6.
      expect(bars.map { |b| b.text.split("\n").first.length }).to all(eq(cols / 3))
      expect(three.css(".pito-heatmap__xticks span").map(&:text)).to eq(%w[q1 q2 q3])
    end

    it "still spans the full canvas for a non-divisor N (remainder to the leftmost bars)" do
      five = render_inline(described_class.new(values: [ 1, 2, 3, 4, 5 ], caption: "", labels: %w[a b c d e]))
      widths = five.css(".pito-heatmap__bar").map { |b| b.text.split("\n").first.length }
      expect(widths).to eq([ 9, 9, 8, 8, 8 ]) # 42 = 9+9+8+8+8
      expect(widths.sum).to eq(cols)
      expect(five.at_css(".pito-heatmap__bars")["style"]).to include("--pito-plot-w: #{cols}ch")
    end

    it "centres non-preset labels per-bar via proportional fr tracks (preset emits none)" do
      five = render_inline(described_class.new(values: [ 1, 2, 3, 4, 5 ], caption: "", labels: %w[a b c d e]))
      expect(five.at_css(".pito-heatmap__xticks")["style"]).to include("--pito-heatmap-xtick-cols: 9fr 9fr 8fr 8fr 8fr")
      # The 7-weekday preset keeps its stylesheet tracks — no inline override.
      expect(node.at_css(".pito-heatmap__xticks")["style"]).to be_nil
    end

    it "omits the x-tick row when labels are omitted for a non-weekday N" do
      bare = render_inline(described_class.new(values: [ 1, 2, 3 ], caption: ""))
      expect(bare.css(".pito-heatmap__bar").size).to eq(3)
      expect(bare.at_css(".pito-heatmap__xticks")).to be_nil
    end

    it "accepts the width cap exactly: COLS one-cell bars" do
      maxed = render_inline(described_class.new(values: (1..cols).to_a, caption: "", labels: (1..cols).map(&:to_s)))
      widths = maxed.css(".pito-heatmap__bar").map { |b| b.text.split("\n").first.length }
      expect(widths).to eq(Array.new(cols, 1))
    end

    it "refuses N above the width cap (a bar can't shrink below one cell) → no-data weekday canvas" do
      over = render_inline(described_class.new(values: (0..cols).to_a, caption: ""))
      expect(over.css(".pito-heatmap__bar").size).to eq(7)
      expect(over.css(".pito-heatmap__xticks span").map(&:text)).to eq(%w[Mo Tu We Th Fr Sa Su])
      heats = over.css(".pito-heatmap__bar").map { |b| b["style"][/--pito-heat: ([0-9.]+)/, 1].to_f }
      expect(heats).to all(eq(0.5))
    end

    it "refuses N=1 (nothing to compare) → no-data weekday canvas" do
      one = render_inline(described_class.new(values: [ 5 ], caption: "", labels: %w[x]))
      expect(one.css(".pito-heatmap__bar").size).to eq(7)
      expect(one.css(".pito-heatmap__xticks span").map(&:text)).to eq(%w[Mo Tu We Th Fr Sa Su])
    end

    it "refuses a labels/values length mismatch → no-data weekday canvas" do
      mismatch = render_inline(described_class.new(values: [ 1, 2, 3 ], caption: "", labels: %w[a b]))
      expect(mismatch.css(".pito-heatmap__bar").size).to eq(7)
      heats = mismatch.css(".pito-heatmap__bar").map { |b| b["style"][/--pito-heat: ([0-9.]+)/, 1].to_f }
      expect(heats).to all(eq(0.5))
    end
  end
end
