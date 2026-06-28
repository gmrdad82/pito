# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::ScaffoldComponent, type: :component do
  let(:intro) { "My Channel, by the numbers." }

  # ── Pending state ────────────────────────────────────────────────────────────

  describe "pending mode" do
    subject(:node) { render_inline(described_class.new(intro:, pending: true)) }

    it "renders the intro text" do
      expect(node.text).to include(intro)
    end

    it "renders a data-pito-ts-slot span inside the intro wrapper" do
      expect(node.css(".pito-analytics-enhanced__intro [data-pito-ts-slot]")).not_to be_empty
    end

    it "does not render the scalars grid" do
      expect(node.css(".pito-analytics-scalars")).to be_empty
    end

    it "does not render any metric pairs" do
      expect(node.css(".pito-analytics-scalars__pair")).to be_empty
    end

    it "has the outer pito-analytics-enhanced class" do
      expect(node.css(".pito-analytics-enhanced")).not_to be_empty
    end

    it "renders an html_safe intro raw (subject-shimmer span survives)" do
      html  = Pito::Copy.render_html("pito.copy.analyze.system.intro", { title: "My Channel", period: "7d" }, shimmer: [ :title ], reference: [ :period ])
      node2 = render_inline(described_class.new(intro: html, pending: true))
      expect(node2.css(".pito-analytics-enhanced__intro span.pito-subject-shimmer")).not_to be_empty
    end

    it "renders a plain (jsonb round-tripped) intro string so a stored shimmer span survives" do
      stored = Pito::Copy.render_html("pito.copy.analyze.system.intro", { title: "My Channel", period: "7d" }, shimmer: [ :title ], reference: [ :period ]).to_str
      node2  = render_inline(described_class.new(intro: stored, pending: true))
      expect(node2.css(".pito-analytics-enhanced__intro span.pito-subject-shimmer")).not_to be_empty
    end
  end

  # ── Ready state: cells present ───────────────────────────────────────────────

  describe "ready mode with cells" do
    let(:cells) do
      [
        { label: "Views",          value: "1" },
        { label: "Subscribers",    value: "0" },
        { label: "Liked",          value: "1" }
      ]
    end

    subject(:node) { render_inline(described_class.new(intro:, cells:)) }

    it "renders the intro text" do
      expect(node.text).to include(intro)
    end

    it "renders a data-pito-ts-slot span inside the intro wrapper" do
      expect(node.css(".pito-analytics-enhanced__intro [data-pito-ts-slot]")).not_to be_empty
    end

    it "renders the scalars grid (.pito-analytics-scalars)" do
      expect(node.css(".pito-analytics-scalars")).not_to be_empty
    end

    it "renders one .pito-analytics-scalars__pair per cell" do
      expect(node.css(".pito-analytics-scalars__pair").length).to eq(cells.length)
    end

    it "renders the correct labels in order" do
      labels = node.css(".pito-analytics-scalars__label").map(&:text)
      expect(labels).to eq(cells.map { |c| c[:label] })
    end

    it "renders the correct values in order" do
      values = node.css(".pito-analytics-scalars__value").map(&:text)
      expect(values).to eq(cells.map { |c| c[:value] })
    end

    it "renders '1' for pulled metrics and '0' for absent ones" do
      values = node.css(".pito-analytics-scalars__value").map(&:text)
      expect(values).to eq(%w[1 0 1])
    end
  end

  # ── Ready state: empty cells ─────────────────────────────────────────────────

  describe "ready mode with no cells" do
    subject(:node) { render_inline(described_class.new(intro:)) }

    it "renders the scalars grid (present but empty)" do
      expect(node.css(".pito-analytics-scalars")).not_to be_empty
    end

    it "renders no metric pairs" do
      expect(node.css(".pito-analytics-scalars__pair")).to be_empty
    end

    it "still renders the intro" do
      expect(node.text).to include(intro)
    end
  end
end
