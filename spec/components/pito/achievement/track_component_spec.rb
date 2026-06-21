# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::TrackComponent do
  def render_track(label:, current_value:)
    render_inline(described_class.new(label: label, current_value: current_value))
  end

  # ── Label rendering ───────────────────────────────────────────

  describe "label rendering" do
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    it "renders the label verbatim (title-case preserved)" do
      expect(node.css(".pito-achievement-track__label").text).to include("Subs")
    end

    it "does not uppercase the label" do
      expect(node.css(".pito-achievement-track__label").text).not_to include("SUBS")
    end
  end

  # ── Responsive flex layout ─────────────────────────────────────
  #
  # The track must use a full-width flex rail rather than a fixed-character
  # white-space:pre layout, so it auto-adjusts when the sidebar opens/closes.

  describe "responsive flex layout" do
    subject(:node) { render_track(label: "Subs", current_value: 0) }

    it "renders the full-width rail container" do
      expect(node.css(".pito-achievement-track__rail")).not_to be_empty
    end

    it "renders exactly 22 cell columns inside the rail" do
      expect(node.css(".pito-achievement-track__rail .pito-achievement-track__cell").count).to eq(22)
    end

    it "renders exactly 21 connector spans between cells" do
      expect(node.css(".pito-achievement-track__rail .pito-achievement-track__connector").count).to eq(21)
    end

    it "nests each dot inside a cell column (not directly in the rail)" do
      # All dot spans must be descendants of a __cell, not direct rail children.
      orphan_dots = node.css(".pito-achievement-track__rail > .pito-achievement-track__dot")
      expect(orphan_dots).to be_empty
    end
  end

  # ── Dot count ─────────────────────────────────────────────────

  describe "dot count" do
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    it "renders exactly one dot span per SERIES entry (22 total)" do
      expect(node.css(".pito-achievement-track__dot").count).to eq(22)
    end
  end

  # ── Glyph distribution ────────────────────────────────────────

  describe "glyph distribution" do
    context "with current_value: 25" do
      # Thresholds ≤ 25: 1, 2, 5, 10, 20  (5 reached; highest = 20 → ◉)
      # Thresholds > 25: 50, 100, …, 10M  (17 upcoming → ○)
      subject(:node) { render_track(label: "Subs", current_value: 25) }

      it "renders 4 filled dots (●) for thresholds below the standing milestone" do
        expect(node.text.count("●")).to eq(4)
      end

      it "renders 1 standing dot (◉) for the highest reached threshold (20)" do
        expect(node.text.count("◉")).to eq(1)
      end

      it "renders 17 upcoming dots (○)" do
        expect(node.text.count("○")).to eq(17)
      end
    end

    context "with current_value: 0" do
      subject(:node) { render_track(label: "Subs", current_value: 0) }

      it "renders all 22 dots as upcoming (○)" do
        expect(node.text.count("○")).to eq(22)
      end

      it "renders no standing dot (◉)" do
        expect(node.text.count("◉")).to eq(0)
      end
    end
  end

  # ── Dot colors ────────────────────────────────────────────────

  describe "dot colors" do
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    it "thresholds 1, 2, 5 (muted tier) carry data-accent='muted'" do
      expect(node.css(".pito-achievement-track__dot[data-accent='muted']")).not_to be_empty
    end

    it "thresholds 10, 20 (green tier) carry data-accent='green'" do
      green_dots = node.css(".pito-achievement-track__dot[data-accent='green']")
      expect(green_dots).not_to be_empty
    end

    it "upcoming dots have the --upcoming modifier class" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.count).to eq(17)
    end

    it "upcoming dots carry no data-accent attribute" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.map { |el| el["data-accent"] }.compact).to be_empty
    end
  end

  # ── Value labels ──────────────────────────────────────────────

  describe "value labels" do
    subject(:node) { render_track(label: "Views", current_value: 0) }

    it "contains the CompactCount label '1K'" do
      expect(node.text).to include("1K")
    end

    it "contains the CompactCount label '500K'" do
      expect(node.text).to include("500K")
    end

    it "contains the CompactCount label '10M'" do
      expect(node.text).to include("10M")
    end

    it "renders value labels inside cell columns" do
      values_in_cells = node.css(".pito-achievement-track__cell .pito-achievement-track__value")
      expect(values_in_cells.count).to eq(22)
    end
  end
end
