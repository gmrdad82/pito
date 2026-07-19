# frozen_string_literal: true

require "rails_helper"

# G127: badges are FILLED material chips (data-material), theme-agnostic.
RSpec.describe Pito::Achievement::BadgeComponent, type: :component do
  include ActiveSupport::Testing::TimeHelpers

  def render_badge(threshold:, metric: "views", scope: "Video", form: :extended, unlocked_on: Date.new(2026, 6, 15))
    render_inline(described_class.new(threshold:, metric:, scope:, form:, unlocked_on:))
  end

  it "renders a .pito-shiny chip with its material as data-material" do
    node = render_badge(threshold: 1)
    chip = node.css(".pito-shiny").first
    expect(chip).to be_present
    expect(chip["data-material"]).to eq("wood")
  end

  it "computes the material from the SCOPE's ladder (same threshold, different stone)" do
    vid  = render_badge(threshold: 20_000, scope: "Video").css(".pito-shiny").first
    chan = render_badge(threshold: 20_000, scope: "Channel").css(".pito-shiny").first
    expect(vid["data-material"]).to eq("pearl")   # 20K sits high on the vid 1M ladder
    expect(chan["data-material"]).to eq("jade")   # ...but mid on the channel 50M ladder
  end

  it "marks pearl/opal/diamond chips iridescent" do
    node = render_badge(threshold: 1_000_000, scope: "Video") # vid views pinnacle -> opal
    expect(node.css(".pito-shiny").first["class"]).to include("pito-shiny--iridescent")
  end

  it "renders channel-subs awards with the award modifier and metal material" do
    node = render_badge(threshold: 100_000, metric: "subs", scope: "Channel")
    chip = node.css(".pito-shiny").first
    expect(chip["data-material"]).to eq("silver")
    expect(chip["class"]).to include("pito-shiny--award")
  end

  it "faces the badge with value + pluralized word" do
    expect(render_badge(threshold: 1).text).to include("1 View")
    expect(render_badge(threshold: 1_000).text).to include("1K Views")
  end

  it "extended form appends the unlock date (house month-granularity — current year drops the year); compact omits it" do
    travel_to(Time.zone.local(2026, 7, 19)) do
      expect(render_badge(threshold: 5, unlocked_on: Date.new(2026, 6, 15)).css(".pito-shiny__date").first.text).to eq("Jun")
      node = render_badge(threshold: 5, form: :compact)
      expect(node.css(".pito-shiny__date")).to be_empty
      expect(node.css(".pito-shiny").first["class"]).to include("pito-shiny--compact")
    end
  end

  it "extended form carries the '%y suffix for an unlock date from another year" do
    travel_to(Time.zone.local(2026, 7, 19)) do
      expect(render_badge(threshold: 5, unlocked_on: Date.new(2025, 6, 15)).css(".pito-shiny__date").first.text).to eq("Jun '25")
    end
  end

  it "staggers the gleam via a 20-step shinies-specific offset class (G128)" do
    expect(render_badge(threshold: 5).css(".pito-shiny").first["class"]).to match(/pito-shiny-s(\d|1\d)\b/)
  end

  it "spreads distinct badges across many stagger buckets" do
    classes = (1..20).map do |i|
      render_badge(threshold: 10**(i % 6), metric: %w[views likes comments][i % 3])
        .css(".pito-shiny").first["class"][/pito-shiny-s\d+/]
    end
    expect(classes.uniq.size).to be > 4
  end
end
