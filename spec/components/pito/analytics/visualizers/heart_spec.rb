# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Visualizers::Heart do
  def render_hearts(hearts:, caption: "Likes vs Dislikes: 92.2% lifetime", **opts)
    render_inline(described_class.new(hearts:, caption:, **opts))
  end

  def braille?(text)
    text.chars.any? { |c| c.ord.between?(0x2800, 0x28FF) }
  end

  let(:two_hearts) do
    [ { score: 100.0, color: :red,    likes: 7,   dislikes: 0 },
      { score: 60.0,  color: :purple, likes: 600, dislikes: 400 } ]
  end

  it "reuses the .pito-metric container chrome (unity with the area chart)" do
    node = render_hearts(hearts: two_hearts)
    wrapper = node.css(".pito-metric.pito-metric--heart").first
    expect(wrapper).to be_present
    expect(wrapper["data-controller"]).to eq("pito--area-chart-reveal")
    expect(node.css(".pito-metric__chart")).to be_present
  end

  it "renders one row-block of braille glyphs per canvas row (reveal targets)" do
    node = render_hearts(hearts: two_hearts, rows: 10)
    rows = node.css(".pito-metric__hrow")
    expect(rows.size).to eq(10)
    expect(rows.map { |r| r["data-pito--area-chart-reveal-target"] }).to all(eq("row"))
    expect(braille?(node.css(".pito-metric__plot").text)).to be(true)
  end

  it "colours each heart's sub-spans via --heart-color (red subject / purple channel)" do
    node   = render_hearts(hearts: two_hearts)
    colors = node.css(".pito-hfill").map { |n| n["style"] }.join(" ")
    expect(colors).to include("--heart-color: var(--accent-red)")
    expect(colors).to include("--heart-color: var(--accent-purple)")
  end

  it "dims the rim above the fill (.is-outline) for a partially-filled heart" do
    # The 60% channel heart leaves an empty top → at least one outline sub-span.
    node = render_hearts(hearts: two_hearts)
    expect(node.css(".pito-hfill.is-outline")).to be_present
  end

  it "fully fills a 100% heart (no outline sub-spans in it)" do
    node = render_hearts(hearts: [ { score: 100.0, color: :red, likes: 7, dislikes: 0 } ])
    expect(node.css(".pito-hfill.is-outline")).to be_empty
  end

  it "renders a likes/dislikes legend per heart with thumb icons" do
    node = render_hearts(hearts: two_hearts)
    legends = node.css(".pito-metric__hlegend-item")
    expect(legends.size).to eq(2)
    expect(node.css(".pito-metric__hlegend svg").size).to eq(4) # thumbs up + down × 2
    expect(legends.first.text).to include("7").and include("0").and include("100.00%")
  end

  it "renders the caption in the shared .pito-metric__caption" do
    node = render_hearts(hearts: two_hearts, caption: "the crowd has spoken")
    expect(node.css(".pito-metric__caption").text).to include("the crowd has spoken")
  end

  it "does NOT render an empty .pito-metric__caption <p> when caption is blank" do
    node = render_hearts(hearts: two_hearts, caption: "")
    expect(node.at_css(".pito-metric__caption")).to be_nil
  end

  it "renders a single heart when given one (channel-only)" do
    node = render_hearts(hearts: [ { score: 88.0, color: :purple, likes: 5400, dislikes: 600 } ])
    expect(node.css(".pito-metric__hlegend-item").size).to eq(1)
  end

  it "sizes the row block to the full chart width (caption parity) for 1 or 2 hearts" do
    width = described_class::COLS # inherited area-chart width
    one   = render_hearts(hearts: [ { score: 88.0, color: :purple, likes: 5400, dislikes: 600 } ])
    two   = render_hearts(hearts: two_hearts)
    expect(one.css(".pito-metric__hrow").first.text.length).to eq(width)
    expect(two.css(".pito-metric__hrow").first.text.length).to eq(width)
  end

  it "renders a faint background dot grid behind the hearts" do
    node = render_hearts(hearts: two_hearts, rows: 10)
    bg = node.css(".pito-metric__bg")
    expect(bg).to be_present
    expect(bg.css(".pito-metric__bg-row").size).to eq(10)
    expect(braille?(bg.text)).to be(true)
  end
end
