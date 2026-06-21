# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::BadgeComponent do
  # Convenience: render a badge and split into the three box lines.
  def badge_lines(threshold:, metric:, unlocked_on: nil)
    node = render_inline(described_class.new(threshold: threshold, metric: metric, unlocked_on: unlocked_on))
    node.css(".pito-achievement-badge").text.split("\n")
  end

  # ── Box structure ──────────────────────────────────────────────
  # Uses :views (rounded light style) as the generic structural specimen —
  # per-metric corner/fill glyphs are asserted in the "border glyphs" block.

  describe "box structure" do
    let(:lines) { badge_lines(threshold: 1_000, metric: :views, unlocked_on: Date.new(2026, 6, 20)) }

    it "renders three lines" do
      expect(lines.length).to eq(3)
    end

    it "top border starts with ╭ and ends with ╮ (rounded light for views)" do
      expect(lines[0]).to start_with("╭").and(end_with("╮"))
    end

    it "middle line starts with │ and ends with │ (rounded light for views)" do
      expect(lines[1]).to start_with("│").and(end_with("│"))
    end

    it "bottom border starts with ╰ and ends with ╯ (rounded light for views)" do
      expect(lines[2]).to start_with("╰").and(end_with("╯"))
    end

    it "top border inner run contains only ─ chars" do
      inner = lines[0][1..-2]
      expect(inner).to match(/\A─+\z/)
    end
  end

  # ── Border glyphs per metric ────────────────────────────────────

  describe "border glyphs per metric" do
    EXPECTED_BORDERS = {
      subs:          { tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║" },
      subs_gained:   { tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║" },
      views:         { tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│" },
      watched_hours: { tl: "┌", tr: "┐", bl: "└", br: "┘", h: "┈", v: "┊" },
      likes:         { tl: "┌", tr: "┐", bl: "└", br: "┘", h: "╌", v: "╎" },
      comments:      { tl: "┏", tr: "┓", bl: "┗", br: "┛", h: "━", v: "┃" }
    }.freeze

    EXPECTED_BORDERS.each do |metric, glyphs|
      context "metric: #{metric}" do
        let(:lines) { badge_lines(threshold: 100, metric: metric) }

        it "top-left corner is '#{glyphs[:tl]}'" do
          expect(lines[0]).to start_with(glyphs[:tl])
        end

        it "top-right corner is '#{glyphs[:tr]}'" do
          expect(lines[0]).to end_with(glyphs[:tr])
        end

        it "top horizontal fill uses only '#{glyphs[:h]}'" do
          inner = lines[0][1..-2]
          expect(inner).to match(/\A#{Regexp.escape(glyphs[:h])}+\z/)
        end

        it "middle vertical bars are '#{glyphs[:v]}'" do
          expect(lines[1]).to start_with(glyphs[:v]).and(end_with(glyphs[:v]))
        end

        it "bottom-left corner is '#{glyphs[:bl]}'" do
          expect(lines[2]).to start_with(glyphs[:bl])
        end

        it "bottom-right corner is '#{glyphs[:br]}'" do
          expect(lines[2]).to end_with(glyphs[:br])
        end
      end
    end
  end

  # ── Abbreviation rendering ────────────────────────────────────

  describe "abbreviation rendering" do
    {
      views:         "V",
      likes:         "L",
      comments:      "C",
      watched_hours: "W",
      subs:          "S",
      subs_gained:   "S"
    }.each do |metric, expected_abbr|
      it "renders '#{expected_abbr}' abbreviation for #{metric}" do
        lines = badge_lines(threshold: 100, metric: metric)
        # middle content: value + space + abbr (+ optional date)
        expect(lines[1]).to include("100 #{expected_abbr}")
      end
    end

    it "renders '100 V' (not 'Views') on the badge face" do
      lines = badge_lines(threshold: 100, metric: :views)
      expect(lines[1]).to include("100 V")
      expect(lines[1]).not_to include("Views")
    end

    it "renders '2 W' (not 'Clocks') on the badge face" do
      lines = badge_lines(threshold: 2, metric: :watched_hours)
      expect(lines[1]).to include("2 W")
      expect(lines[1]).not_to include("Clocks")
    end
  end

  # ── Fixed-width invariance ────────────────────────────────────

  describe "fixed-width invariance (INNER_WIDTH = #{described_class::INNER_WIDTH})" do
    let(:variants) do
      [
        { threshold: 1,          metric: :subs },
        { threshold: 500_000,    metric: :watched_hours, unlocked_on: Date.new(2026, 8, 1) },
        { threshold: 500_000,    metric: :comments },
        { threshold: 1_000_000,  metric: :subs },
        { threshold: 2,          metric: :likes,         unlocked_on: Date.new(2026, 6, 20) }
      ]
    end

    it "all badges have DASH_COUNT horizontal-fill chars in the top border" do
      fill_lengths = variants.map { |opts| badge_lines(**opts).first[1..-2].length }
      expect(fill_lengths.uniq).to eq([ described_class::DASH_COUNT ]),
        "Expected all inner fills to be #{described_class::DASH_COUNT} chars but got: #{fill_lengths.inspect}"
    end

    it "all badges produce the same total top-line character length" do
      lengths = variants.map { |opts| badge_lines(**opts).first.length }
      expect(lengths.uniq.size).to eq(1), "Expected identical line lengths but got: #{lengths.inspect}"
    end

    it "all middle lines have the same total character length as the top border" do
      variants.each do |opts|
        lines = badge_lines(**opts)
        expect(lines[1].length).to eq(lines[0].length),
          "Middle line length #{lines[1].length} != top line #{lines[0].length} for #{opts.inspect}"
      end
    end

    it "INNER_WIDTH constant is 18" do
      expect(described_class::INNER_WIDTH).to eq(18)
    end

    it "DASH_COUNT constant equals INNER_WIDTH (18)" do
      expect(described_class::DASH_COUNT).to eq(18)
      expect(described_class::DASH_COUNT).to eq(described_class::INNER_WIDTH)
    end
  end

  # ── Centering ─────────────────────────────────────────────────

  describe "content centering" do
    it "longest badge (500K W · Jun '26, 16 chars) has 1 leading space in content area" do
      lines = badge_lines(threshold: 500_000, metric: :watched_hours, unlocked_on: Date.new(2026, 6, 20))
      # Middle line: "│" + content_area (18 chars) + "│" (no explicit padding spaces)
      # Content: " 500K W · Jun '26 " (1 left, 1 right centering for 16-char payload)
      content_area = lines[1][1..-2]  # strip the "│" bars
      expect(content_area.length).to eq(described_class::INNER_WIDTH)
      expect(content_area).to start_with(" ")
      expect(content_area).to end_with(" ")
    end

    it "short badge (2 L · Jun '26, 13 chars) has more than 1 leading space in content area" do
      lines = badge_lines(threshold: 2, metric: :likes, unlocked_on: Date.new(2026, 6, 20))
      content_area = lines[1][1..-2]
      expect(content_area.length).to eq(described_class::INNER_WIDTH)
      # 5 spare chars split ≥2 on the left
      expect(content_area).to start_with("  ")
    end

    it "badge without date (1 S, 3 chars) has many leading spaces in content area" do
      lines = badge_lines(threshold: 1, metric: :subs)
      content_area = lines[1][1..-2]
      expect(content_area.length).to eq(described_class::INNER_WIDTH)
      # 15 spare chars — left pad = 7
      expect(content_area).to start_with("       ")
    end
  end

  # ── data-accent tier mapping ──────────────────────────────────

  describe "data-accent attribute" do
    {
             1 => "muted",
            10 => "green",
           100 => "cyan",
         1_000 => "blue",
        10_000 => "purple",
       100_000 => "orange",
     1_000_000 => "yellow",
    10_000_000 => "pito"
    }.each do |threshold, expected_accent|
      it "maps threshold #{threshold} to data-accent=#{expected_accent}" do
        node = render_inline(described_class.new(threshold: threshold, metric: :subs))
        expect(node.css(".pito-achievement-badge[data-accent='#{expected_accent}']")).not_to be_empty
      end
    end
  end

  # ── Value formatting ──────────────────────────────────────────

  describe "value formatting via CompactCount" do
    {
         1_000 => "1K",
       500_000 => "500K",
    10_000_000 => "10M",
             5 => "5"
    }.each do |threshold, expected_value|
      it "formats #{threshold} as '#{expected_value}' in the content line" do
        lines = badge_lines(threshold: threshold, metric: :subs)
        expect(lines[1]).to include(expected_value)
      end
    end
  end

  # ── Date rendering ────────────────────────────────────────────

  describe "date rendering" do
    context "with unlocked_on set" do
      subject(:node) do
        render_inline(described_class.new(threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026, 8, 1)))
      end

      it "includes · Aug '26 in the content line text (middot-separated, no parens)" do
        lines = node.css(".pito-achievement-badge").text.split("\n")
        expect(lines[1]).to include("· Aug '26")
      end

      it "renders the date inside a .pito-achievement-badge__date span" do
        span = node.css(".pito-achievement-badge__date")
        expect(span).not_to be_empty
        expect(span.text).to eq("· Aug '26")
      end
    end

    context "with unlocked_on nil" do
      subject(:node) do
        render_inline(described_class.new(threshold: 1_000, metric: :subs))
      end

      it "does not include a middot-separated date in the content line" do
        lines = node.css(".pito-achievement-badge").text.split("\n")
        expect(lines[1]).not_to match(/·\s+[A-Z][a-z]{2}\s+'/)
      end

      it "does not render a .pito-achievement-badge__date span" do
        expect(node.css(".pito-achievement-badge__date")).to be_empty
      end
    end
  end
end
