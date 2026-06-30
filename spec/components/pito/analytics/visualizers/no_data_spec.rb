# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Visualizers::NoData, type: :component do
  subject(:node) { render_inline(described_class.new) }

  # ── Row count ────────────────────────────────────────────────────────────────

  it "renders 11 rows (full Base canvas) by default" do
    rows = node.css(".pito-metric__row")
    expect(rows.size).to eq(11)
  end

  it "renders 11 rows when size: :regular" do
    regular = render_inline(described_class.new(size: :regular))
    expect(regular.css(".pito-metric__row").size).to eq(Pito::Analytics::Visualizers::Base::ROWS)
    expect(Pito::Analytics::Visualizers::Base::ROWS).to eq(11)
  end

  it "renders 2 rows (sparkline canvas) when size: :compact" do
    compact = render_inline(described_class.new(size: :compact))
    expect(compact.css(".pito-metric__row").size).to eq(Pito::Analytics::Visualizers::Sparkline::ROWS)
    expect(Pito::Analytics::Visualizers::Sparkline::ROWS).to eq(2)
  end

  # ── Shimmer ──────────────────────────────────────────────────────────────────

  it "applies ONE shared shimmer-offset bucket to every canvas row (:regular)" do
    rows = node.css(".pito-metric__row")
    buckets = rows.map { |r| r["class"][/pito-shimmer-d\d+/] }
    expect(buckets).to all(match(/\Apito-shimmer-d\d+\z/))
    expect(buckets.uniq.size).to eq(1)
  end

  it "applies shimmer-offset class to every canvas row in :compact mode" do
    compact = render_inline(described_class.new(size: :compact))
    rows = compact.css(".pito-metric__row")
    expect(rows.size).to eq(2)
    buckets = rows.map { |r| r["class"][/pito-shimmer-d\d+/] }
    expect(buckets).to all(match(/\Apito-shimmer-d\d+\z/))
  end

  it "uses the same shimmer class selector (.pito-metric__row) as the area chart rows" do
    # NoData blank rows MUST wear .pito-metric__row so the identical 135-deg
    # pito-blue sweep CSS applies without any extra selector.
    expect(node.css(".pito-metric__row").size).to eq(11)
  end

  # ── Background layer ─────────────────────────────────────────────────────────

  it "renders the dotted-paper bg layer" do
    expect(node.at_css(".pito-metric__bg")).to be_present
  end

  it "bg layer shrinks to 2 rows in :compact mode" do
    compact = render_inline(described_class.new(size: :compact))
    expect(compact.css(".pito-metric__bg-row").size).to eq(2)
  end

  it "renders VISIBLE dot ink (not blank braille) so the shimmer has glyphs to clip" do
    dot   = [ 0x2802 ].pack("U") # ⠂ BG_DOT
    blank = [ 0x2800 ].pack("U") # ⠀
    rows_text = node.css(".pito-metric__row").map(&:text).join
    expect(rows_text).to include(dot)
    expect(rows_text).not_to include(blank)
  end
end
