# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::BadgeComponent do
  # Convenience: render a badge and split into the three box lines.
  def badge_lines(threshold:, label:, unlocked_on: nil)
    node = render_inline(described_class.new(threshold: threshold, label: label, unlocked_on: unlocked_on))
    node.css(".pito-achievement-badge").text.split("\n")
  end

  # ── Box structure ──────────────────────────────────────────────

  describe "box structure" do
    let(:lines) { badge_lines(threshold: 1_000, label: "Subs", unlocked_on: Date.new(2026, 6, 20)) }

    it "renders three lines" do
      expect(lines.length).to eq(3)
    end

    it "top border starts with ╭ and ends with ╮" do
      expect(lines[0]).to start_with("╭").and(end_with("╮"))
    end

    it "middle line starts with │ and ends with │" do
      expect(lines[1]).to start_with("│").and(end_with("│"))
    end

    it "bottom border starts with ╰ and ends with ╯" do
      expect(lines[2]).to start_with("╰").and(end_with("╯"))
    end

    it "top border inner run contains only ─ chars" do
      inner = lines[0][1..-2]
      expect(inner).to match(/\A─+\z/)
    end
  end

  # ── Fixed-width invariance ────────────────────────────────────

  describe "fixed-width invariance" do
    let(:variants) do
      [
        { threshold: 1,          label: "Subs" },
        { threshold: 500_000,    label: "Watched", unlocked_on: Date.new(2026, 6, 20) },
        { threshold: 500_000,    label: "Comms" },
        { threshold: 10_000_000, label: "Subs" }
      ]
    end

    it "all badges produce the same top-border dash count" do
      dash_counts = variants.map { |opts| badge_lines(**opts).first.count("─") }
      expect(dash_counts.uniq.size).to eq(1), "Expected identical dash counts but got: #{dash_counts.inspect}"
    end

    it "all badges produce the same total top-line character length" do
      lengths = variants.map { |opts| badge_lines(**opts).first.length }
      expect(lengths.uniq.size).to eq(1), "Expected identical line lengths but got: #{lengths.inspect}"
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
        node = render_inline(described_class.new(threshold: threshold, label: "Subs"))
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
        lines = badge_lines(threshold: threshold, label: "Subs")
        expect(lines[1]).to include(expected_value)
      end
    end
  end

  # ── Singular / plural label rendering ────────────────────────

  describe "singular and plural label rendering" do
    it "renders '1 Sub' in the content line when threshold is 1 and label is 'Sub'" do
      lines = badge_lines(threshold: 1, label: "Sub")
      expect(lines[1]).to include("1 Sub")
    end

    it "renders '1K Subs' in the content line when threshold is 1_000 and label is 'Subs'" do
      lines = badge_lines(threshold: 1_000, label: "Subs")
      expect(lines[1]).to include("1K Subs")
    end
  end

  # ── Date rendering ────────────────────────────────────────────

  describe "date rendering" do
    context "with unlocked_on set" do
      subject(:node) do
        render_inline(described_class.new(threshold: 1_000, label: "Subs", unlocked_on: Date.new(2026, 6, 20)))
      end

      it "includes (20-06-2026) in the content line text" do
        lines = node.css(".pito-achievement-badge").text.split("\n")
        expect(lines[1]).to include("(20-06-2026)")
      end

      it "renders the date inside a .pito-achievement-badge__date span" do
        span = node.css(".pito-achievement-badge__date")
        expect(span).not_to be_empty
        expect(span.text).to eq("(20-06-2026)")
      end
    end

    context "with unlocked_on nil" do
      subject(:node) do
        render_inline(described_class.new(threshold: 1_000, label: "Subs"))
      end

      it "does not include a parenthesised date in the content line" do
        lines = node.css(".pito-achievement-badge").text.split("\n")
        expect(lines[1]).not_to match(/\(\d{2}-\d{2}-\d{4}\)/)
      end

      it "does not render a .pito-achievement-badge__date span" do
        expect(node.css(".pito-achievement-badge__date")).to be_empty
      end
    end
  end
end
