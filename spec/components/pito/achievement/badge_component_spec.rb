# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::BadgeComponent do
  def render_badge(threshold:, metric:, unlocked_on: nil)
    render_inline(described_class.new(threshold: threshold, metric: metric, unlocked_on: unlocked_on))
  end

  # ── Single uniform bordered element (no per-metric box drawing) ──

  describe "uniform bordered badge" do
    it "renders exactly one .pito-achievement-badge element regardless of metric" do
      %i[subs subs_gained views watched_hours likes comments].each do |metric|
        node = render_badge(threshold: 100, metric: metric)
        expect(node.css(".pito-achievement-badge").length).to eq(1)
      end
    end

    it "renders no box-drawing glyphs (border is pure CSS now)" do
      node = render_badge(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 8, 1))
      text = node.css(".pito-achievement-badge").text
      box_drawing = /[╔╗╚╝═║╭╮╰╯─│┌┐└┘┈┊╌╎┏┓┗┛━┃]/
      expect(text).not_to match(box_drawing)
    end

    it "uses the same markup shape (no metric-specific border) across metrics" do
      # The badge element carries no metric-derived class/attribute — only the
      # shimmer offset + tier accent vary, never a per-metric border.
      faces = %i[subs views comments].map do |metric|
        node = render_badge(threshold: 100, metric: metric)
        node.css(".pito-achievement-badge").first.name
      end
      expect(faces.uniq).to eq([ "span" ])
    end
  end

  # ── Content: <value> <ABBR> · <Mon 'YY> ─────────────────────────

  describe "content" do
    it "renders value + single-letter abbr on the face" do
      {
        views:         "V",
        likes:         "L",
        comments:      "C",
        watched_hours: "W",
        subs:          "S",
        subs_gained:   "S"
      }.each do |metric, abbr|
        node = render_badge(threshold: 100, metric: metric)
        expect(node.css(".pito-achievement-badge").text).to include("100 #{abbr}")
      end
    end

    it "uses the abbreviation, not the full label word" do
      node = render_badge(threshold: 100, metric: :views)
      text = node.css(".pito-achievement-badge").text
      expect(text).to include("100 V")
      expect(text).not_to include("Views")
    end

    it "formats the value via CompactCount" do
      {
           1_000 => "1K",
         500_000 => "500K",
      10_000_000 => "10M",
               5 => "5"
      }.each do |threshold, formatted|
        node = render_badge(threshold: threshold, metric: :subs)
        expect(node.css(".pito-achievement-badge").text).to include(formatted)
      end
    end
  end

  # ── Date: muted sub-span, distinct from the tier-coloured value ──

  describe "date rendering" do
    context "with unlocked_on set" do
      subject(:node) { render_badge(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 8, 1)) }

      it "renders · Mon 'YY inside a muted .pito-achievement-badge__date span" do
        span = node.css(".pito-achievement-badge__date")
        expect(span).not_to be_empty
        expect(span.text).to eq("· Aug '26")
      end

      it "renders the full face as <value> <ABBR> · <Mon 'YY>" do
        expect(node.css(".pito-achievement-badge").text).to include("1K S · Aug '26")
      end

      it "keeps the date in its own span so CSS mutes it independently of the tier" do
        # The value/abbr live as a direct text node on the badge (tier-coloured),
        # while the date lives only inside the __date span (muted via --fg-dim).
        face = node.css(".pito-achievement-badge").first
        expect(face.css(".pito-achievement-badge__date").length).to eq(1)
        text_without_date = face.text.sub(face.css(".pito-achievement-badge__date").text, "").strip
        expect(text_without_date).to eq("1K S")
      end
    end

    context "with unlocked_on nil" do
      subject(:node) { render_badge(threshold: 1_000, metric: :subs) }

      it "omits the date span entirely" do
        expect(node.css(".pito-achievement-badge__date")).to be_empty
      end

      it "does not include a middot-separated date in the face" do
        expect(node.css(".pito-achievement-badge").text).not_to match(/·\s+[A-Z][a-z]{2}\s+'/)
      end
    end
  end

  # ── Tier colour via data-accent (per threshold) ─────────────────

  describe "data-accent tier mapping" do
    {
             1 => "muted",
            10 => "green",
           100 => "cyan",
         1_000 => "blue",
        10_000 => "purple",
       100_000 => "orange",
     1_000_000 => "yellow",
    10_000_000 => "pito"
    }.each do |threshold, accent|
      it "maps threshold #{threshold} to data-accent=#{accent}" do
        node = render_badge(threshold: threshold, metric: :subs)
        expect(node.css(".pito-achievement-badge[data-accent='#{accent}']")).not_to be_empty
      end
    end
  end

  # ── Perimeter-shimmer stagger offset ────────────────────────────

  describe "shimmer offset class" do
    it "applies a shared .pito-shimmer-dN stagger bucket to the badge" do
      node = render_badge(threshold: 1_000, metric: :subs)
      classes = node.css(".pito-achievement-badge").first["class"]
      expect(classes).to match(/\bpito-shimmer-d\d+\b/)
    end

    it "derives the bucket from a stable threshold+metric key" do
      expected = Pito::Shimmer.offset_class("1000subs")
      node = render_badge(threshold: 1_000, metric: :subs)
      expect(node.css(".pito-achievement-badge.#{expected}")).not_to be_empty
    end
  end
end
