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
end
