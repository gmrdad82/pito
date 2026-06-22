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

  # ── Reached-run shimmer (next-tier colour) ────────────────────
  #
  # Owner-locked: the whole reached run (reached dots + the connectors between
  # them, up to and including the standing ◉) shimmers, coloured by the NEXT
  # unreached tier — not each dot's own tier.

  describe "reached-run shimmer" do
    # current_value: 15 → reached thresholds 1, 2, 5, 10 (4 dots; highest = 10).
    # Next unreached threshold strictly > 15 is 20 → token "green".
    subject(:node) { render_track(label: "Subs", current_value: 15) }

    let(:next_token) { Pito::Achievement::Tier.token_for(20) }

    it "computes the next-tier token from the threshold strictly above the value" do
      expect(next_token).to eq("green")
    end

    it "marks every reached dot with the --reached shimmer class" do
      expect(node.css(".pito-achievement-track__dot--reached").count).to eq(4)
    end

    it "colours every reached dot with the NEXT tier's data-accent (not its own)" do
      accents = node.css(".pito-achievement-track__dot--reached").map { |el| el["data-accent"] }
      expect(accents).to all(eq(next_token))
    end

    it "does not use each reached dot's own tier token (1/2/5 would be muted)" do
      expect(node.css(".pito-achievement-track__dot--reached[data-accent='muted']")).to be_empty
    end

    it "marks the connectors inside the reached run with the --reached shimmer class" do
      # 4 reached dots → 3 connectors strictly between them + the in-progress connector
      # (standing ◉ 10 → next tier 20) = 4 carry the run colour.
      expect(node.css(".pito-achievement-track__connector--reached").count).to eq(4)
    end

    it "colours the reached connectors with the NEXT tier's data-accent" do
      accents = node.css(".pito-achievement-track__connector--reached").map { |el| el["data-accent"] }
      expect(accents).to all(eq(next_token))
    end

    it "staggers reached elements with shared pito-shimmer-dN offset classes" do
      reached = node.css(".pito-achievement-track__dot--reached, .pito-achievement-track__connector--reached")
      expect(reached).to all(satisfy { |el| el["class"] =~ /\bpito-shimmer-d\d+\b/ })
    end
  end

  # ── Upcoming dots stay dim + static ───────────────────────────

  describe "upcoming dots" do
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    it "upcoming dots have the --upcoming modifier class" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.count).to eq(17)
    end

    it "upcoming dots carry no data-accent attribute" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.map { |el| el["data-accent"] }.compact).to be_empty
    end

    it "upcoming dots carry no --reached shimmer class" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.map { |el| el["class"] }).to all(satisfy { |c| !c.include?("--reached") })
    end

    it "connectors beyond the in-progress one stay static (no --reached, no accent)" do
      static_connectors = node.css(".pito-achievement-track__connector").reject do |el|
        el["class"].include?("pito-achievement-track__connector--reached")
      end
      expect(static_connectors.map { |el| el["data-accent"] }.compact).to be_empty
    end
  end

  # ── Top-tier fallback ─────────────────────────────────────────

  describe "top-tier fallback" do
    # Value past the top milestone (10M): every threshold reached, no next tier.
    subject(:node) { render_track(label: "Subs", current_value: 50_000_000) }

    it "renders without raising when there is no next tier" do
      expect { node }.not_to raise_error
    end

    it "falls back to the highest tier's token for the whole reached run" do
      top_token = Pito::Achievement::Tier.token_for(Pito::Achievement::Tier::SERIES.last)
      accents = node.css(".pito-achievement-track__dot--reached").map { |el| el["data-accent"] }
      expect(accents).to all(eq(top_token))
    end

    it "marks all 22 dots as reached when past the top milestone" do
      expect(node.css(".pito-achievement-track__dot--reached").count).to eq(22)
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
