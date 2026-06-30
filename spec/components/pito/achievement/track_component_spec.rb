# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::TrackComponent do
  def render_track(label:, current_value:)
    render_inline(described_class.new(label: label, current_value: current_value))
  end

  # Series indices, for reference:
  #   0:1  1:2  2:5  3:10  4:20  5:50  6:100 7:200 8:500
  #   9:1K 10:2K 11:5K 12:10K 13:20K 14:50K 15:100K 16:200K 17:500K
  #   18:1M 19:2M 20:5M 21:10M
  #
  # Helpers to read the collapsed visible-point set from rendered output.
  def visible_values(node)
    node.css(".pito-achievement-track__cell .pito-achievement-track__value").map(&:text)
  end

  def fmt(threshold)
    Pito::Formatter::CompactCount.call(threshold)
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
  # The track is a full-width flex rail (not a fixed-character white-space:pre
  # layout) so it auto-adjusts when the sidebar opens/closes.

  describe "responsive flex layout" do
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    it "renders the full-width rail container" do
      expect(node.css(".pito-achievement-track__rail")).not_to be_empty
    end

    it "nests each dot inside a cell column (not directly in the rail)" do
      orphan_dots = node.css(".pito-achievement-track__rail > .pito-achievement-track__dot")
      expect(orphan_dots).to be_empty
    end

    it "renders one value label per visible cell" do
      cells  = node.css(".pito-achievement-track__cell").count
      values = node.css(".pito-achievement-track__cell .pito-achievement-track__value").count
      expect(values).to eq(cells)
    end
  end

  # ── Collapsed visible-point set ───────────────────────────────
  #
  # Owner-locked J4 rule: show 1 (always) → … → prev → current → next → … → last
  # (always). The full 22-point series is never rendered.

  describe "collapsed visible-point set" do
    it "never renders all 22 series points" do
      node = render_track(label: "Subs", current_value: 25)
      expect(node.css(".pito-achievement-track__cell").count).to be < 22
    end

    context "middle: current_value 25 (standing 20)" do
      # prev 10, current 20, next 50; plus 1 and last 10M.
      subject(:node) { render_track(label: "Subs", current_value: 25) }

      it "shows exactly [1, 10, 20, 50, 10M]" do
        expect(visible_values(node)).to eq([ fmt(1), fmt(10), fmt(20), fmt(50), fmt(10_000_000) ])
      end

      it "marks 20 as the standing milestone (◉)" do
        expect(node.text.count("◉")).to eq(1)
      end

      it "renders an ellipsis on both skipped sides (1…10 and 50…10M)" do
        expect(node.css(".pito-achievement-track__ellipsis").count).to eq(2)
      end
    end

    context "start: current_value 1 (standing 1)" do
      # prev is below series → left side collapses; no left ellipsis, no dup of 1.
      subject(:node) { render_track(label: "Subs", current_value: 1) }

      it "shows exactly [1, 2, 10M] (1 not duplicated)" do
        expect(visible_values(node)).to eq([ fmt(1), fmt(2), fmt(10_000_000) ])
      end

      it "renders no left ellipsis (1→2 are adjacent) and one right ellipsis" do
        expect(node.css(".pito-achievement-track__ellipsis").count).to eq(1)
      end

      it "marks 1 as the standing milestone (◉)" do
        expect(node.text.count("◉")).to eq(1)
      end
    end

    context "end: current_value 5_000_000 (standing 5M)" do
      # next is 10M (== last) → right side collapses; no right ellipsis, no dup.
      subject(:node) { render_track(label: "Subs", current_value: 5_000_000) }

      it "shows exactly [1, 2M, 5M, 10M] (10M not duplicated)" do
        expect(visible_values(node)).to eq([ fmt(1), fmt(2_000_000), fmt(5_000_000), fmt(10_000_000) ])
      end

      it "renders only the left ellipsis (no dangling right ellipsis)" do
        expect(node.css(".pito-achievement-track__ellipsis").count).to eq(1)
      end
    end

    context "all-reached: current_value past the top (50_000_000)" do
      # current == last (10M); show 1 … prev last with no dangling ellipsis.
      subject(:node) { render_track(label: "Subs", current_value: 50_000_000) }

      it "shows exactly [1, 5M, 10M]" do
        expect(visible_values(node)).to eq([ fmt(1), fmt(5_000_000), fmt(10_000_000) ])
      end

      it "marks 10M as the standing milestone (◉) and renders no upcoming dot" do
        expect(node.text.count("◉")).to eq(1)
        expect(node.css(".pito-achievement-track__dot--upcoming")).to be_empty
      end

      it "renders a single (left) ellipsis only" do
        expect(node.css(".pito-achievement-track__ellipsis").count).to eq(1)
      end
    end

    context "none-reached: current_value 0" do
      # No standing; minimal sensible form 1 ─···─ 10M.
      subject(:node) { render_track(label: "Subs", current_value: 0) }

      it "shows exactly [1, 10M]" do
        expect(visible_values(node)).to eq([ fmt(1), fmt(10_000_000) ])
      end

      it "renders both visible points as upcoming (○), no standing ◉" do
        expect(node.text.count("○")).to eq(2)
        expect(node.text.count("◉")).to eq(0)
      end

      it "renders a single ellipsis bridging the gap" do
        expect(node.css(".pito-achievement-track__ellipsis").count).to eq(1)
      end
    end
  end

  # ── No duplicate points ───────────────────────────────────────

  describe "no duplicate points" do
    [ 0, 1, 2, 25, 5_000_000, 50_000_000 ].each do |value|
      it "renders each value label at most once (current_value: #{value})" do
        labels = visible_values(render_track(label: "Subs", current_value: value))
        expect(labels).to eq(labels.uniq)
      end
    end
  end

  # ── Ellipsis only where thresholds are skipped ────────────────

  describe "ellipsis placement" do
    it "inserts an ellipsis only between non-adjacent visible points" do
      # current_value 5 → standing 5; visible [1, 2, 5, 10, 10M] (indices 0,1,2,3,21):
      # 1-2-5-10 are series-adjacent (no ellipsis); 10…10M skips → one ellipsis.
      node = render_track(label: "Subs", current_value: 5)
      expect(visible_values(node)).to eq([ fmt(1), fmt(2), fmt(5), fmt(10), fmt(10_000_000) ])
      expect(node.css(".pito-achievement-track__ellipsis").count).to eq(1)
    end

    it "renders two ellipses for a deep-middle value with both sides skipped" do
      # current_value 1_000 → standing 1K; visible [1, 500, 1K, 2K, 10M]
      # (indices 0,8,9,10,21): 1…500 skips and 2K…10M skips → two ellipses.
      node = render_track(label: "Subs", current_value: 1_000)
      expect(node.css(".pito-achievement-track__ellipsis").count).to eq(2)
    end

    it "renders the ellipsis as a CONTINUOUS rail (long dash run flanking the middots)" do
      node     = render_track(label: "Subs", current_value: 20)
      ellipsis = node.css(".pito-achievement-track__ellipsis").first
      text     = ellipsis.text
      # Middots stay at the centre…
      expect(text).to include("···")
      # …flanked by a long run of box-drawing dashes on EACH side, so once the
      # CSS centre-clips the over-long string it fills the whole gap edge-to-edge
      # (no empty gaps between the dots and the dashes — that was the broken look).
      expect(text).to match(/─{20,}···─{20,}/)
    end
  end

  # ── Ellipsis shimmer ──────────────────────────────────────────
  #
  # An ellipsis that falls inside the reached run shimmers (carries the reached
  # class + a pito-shimmer-dN stagger + the next-tier data-accent). An ellipsis in
  # the upcoming region stays static (no reached class, no accent).

  describe "ellipsis shimmer" do
    # current_value 25 → standing 20; next tier token from 50.
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    let(:next_token) { Pito::Achievement::Tier.token_for(50) }

    it "shimmers the left (reached) ellipsis: reached class + stagger + accent" do
      left = node.css(".pito-achievement-track__ellipsis--reached")
      expect(left.count).to eq(1)
      expect(left.first["class"]).to match(/\bpito-shimmer-d\d+\b/)
      expect(left.first["data-accent"]).to eq(next_token)
    end

    it "keeps the right (upcoming) ellipsis static: no reached class, no accent" do
      static = node.css(".pito-achievement-track__ellipsis").reject do |el|
        el["class"].include?("pito-achievement-track__ellipsis--reached")
      end
      expect(static.count).to eq(1)
      expect(static.first["data-accent"]).to be_nil
    end
  end

  # ── Reached-run shimmer (next-tier colour) ────────────────────
  #
  # Owner-locked: the whole reached run (reached dots + the joiners between them,
  # up to and including the standing ◉, plus the in-progress joiner) shimmers,
  # coloured by the NEXT unreached tier — not each dot's own tier.

  describe "reached-run shimmer" do
    # current_value 15 → reached 1, 2, 5, 10 (standing 10); next tier from 20.
    # Collapsed visible set: [1, 5, 10, 20, 10M] (indices 0,2,3,4,21).
    subject(:node) { render_track(label: "Subs", current_value: 15) }

    let(:next_token) { Pito::Achievement::Tier.token_for(20) }

    it "computes the next-tier token from the threshold strictly above the value" do
      expect(next_token).to eq("green")
    end

    it "marks every visible reached dot with the --reached shimmer class" do
      # Visible reached dots: 1, 5, 10 → 3.
      expect(node.css(".pito-achievement-track__dot--reached").count).to eq(3)
    end

    it "colours every reached dot with the NEXT tier's data-accent (not its own)" do
      accents = node.css(".pito-achievement-track__dot--reached").map { |el| el["data-accent"] }
      expect(accents).to all(eq(next_token))
    end

    it "does not use each reached dot's own tier token (1/2/5 would be muted)" do
      expect(node.css(".pito-achievement-track__dot--reached[data-accent='muted']")).to be_empty
    end

    it "marks the reached connectors (5→10 and the in-progress 10→20) with --reached" do
      expect(node.css(".pito-achievement-track__connector--reached").count).to eq(2)
    end

    it "colours the reached connectors with the NEXT tier's data-accent" do
      accents = node.css(".pito-achievement-track__connector--reached").map { |el| el["data-accent"] }
      expect(accents).to all(eq(next_token))
    end

    it "staggers reached elements with shared pito-shimmer-dN offset classes" do
      reached = node.css(
        ".pito-achievement-track__dot--reached, " \
        ".pito-achievement-track__connector--reached, " \
        ".pito-achievement-track__ellipsis--reached"
      )
      expect(reached).to all(satisfy { |el| el["class"] =~ /\bpito-shimmer-d\d+\b/ })
    end
  end

  # ── Upcoming dots stay dim + static ───────────────────────────

  describe "upcoming dots" do
    # current_value 25 → visible [1, 10, 20, 50, 10M]; upcoming dots 50 + 10M.
    subject(:node) { render_track(label: "Subs", current_value: 25) }

    it "renders the upcoming visible dots with the --upcoming modifier class" do
      expect(node.css(".pito-achievement-track__dot--upcoming").count).to eq(2)
    end

    it "upcoming dots carry no data-accent attribute" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.map { |el| el["data-accent"] }.compact).to be_empty
    end

    it "upcoming dots carry no --reached shimmer class" do
      upcoming = node.css(".pito-achievement-track__dot--upcoming")
      expect(upcoming.map { |el| el["class"] }).to all(satisfy { |c| !c.include?("--reached") })
    end

    it "joiners beyond the in-progress one stay static (no --reached, no accent)" do
      static = node.css(".pito-achievement-track__connector, .pito-achievement-track__ellipsis").reject do |el|
        el["class"].include?("--reached")
      end
      expect(static.map { |el| el["data-accent"] }.compact).to be_empty
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

    it "marks every visible dot as reached when past the top milestone" do
      expect(node.css(".pito-achievement-track__dot--upcoming")).to be_empty
      expect(node.css(".pito-achievement-track__dot--reached").count).to eq(node.css(".pito-achievement-track__dot").count)
    end
  end

  # ── Value labels ──────────────────────────────────────────────

  describe "value labels" do
    it "renders CompactCount labels for the visible points (e.g. 1, 10M)" do
      node = render_track(label: "Views", current_value: 0)
      expect(node.text).to include("10M")
      expect(visible_values(node)).to include(fmt(1))
    end

    it "renders value labels inside cell columns only" do
      node = render_track(label: "Views", current_value: 25)
      values_in_cells = node.css(".pito-achievement-track__cell .pito-achievement-track__value").count
      all_values      = node.css(".pito-achievement-track__value").count
      expect(values_in_cells).to eq(all_values)
    end
  end

  # ── Per-tier contrast reached-run shimmer (CSS contract) ──────
  #
  # The reached-run sweep highlight must be a per-tier CONTRASTING accent
  # (--pito-track-shimmer), never plain white (--fg-default). The reached-run
  # animation must use LONGHANDS (not the `animation` shorthand) so the per-element
  # .pito-shimmer-dN stagger survives the cascade. The collapsed-track ellipsis
  # joiner must share the same reached-run sweep + reduced-motion guard.

  describe "per-tier contrast shimmer + stagger (CSS)" do
    css = Rails.root.join("app/assets/tailwind/application.css").read

    {
      "muted"  => "cyan",
      "green"  => "yellow",
      "cyan"   => "orange",
      "blue"   => "orange",
      "purple" => "yellow",
      "orange" => "cyan",
      "yellow" => "blue",
      "pito"   => "orange"
    }.each do |tier, contrast|
      it "maps the #{tier} run colour to a contrasting --pito-track-shimmer (--accent-#{contrast})" do
        rule = css[/\.pito-achievement-track \[data-accent="#{tier}"\][^}]*\}/]
        expect(rule).to be_present
        expect(rule).to match(/--pito-track-shimmer:\s*var\(--accent-#{contrast}\)/)
      end
    end

    it "never uses white (--fg-default) as a run's reached-shimmer highlight" do
      expect(css).not_to match(/--pito-track-shimmer:\s*var\(--fg-default\)/)
    end

    # Capture the whole reached-run selector list + block (dots, connectors AND the
    # collapsed-track ellipsis).
    let(:reached_rule) do
      css[/\.pito-achievement-track__dot--reached,\s*\.pito-achievement-track__connector--reached,\s*\.pito-achievement-track__ellipsis--reached\s*\{[^}]*\}/m]
    end

    it "drives the reached-run highlight band from --pito-track-shimmer" do
      expect(reached_rule).to be_present
      expect(reached_rule).to match(/var\(--pito-track-shimmer/)
    end

    it "includes the ellipsis joiner in the reached-run sweep" do
      expect(reached_rule).to be_present
      expect(reached_rule).to include(".pito-achievement-track__ellipsis--reached")
    end

    it "uses animation longhands (no shorthand) so the dN stagger survives" do
      expect(reached_rule).to match(/animation-name:\s*pito-action-shimmer-sweep/)
      expect(reached_rule).not_to match(/^\s*animation:\s/)
    end

    it "honours prefers-reduced-motion for the reached ellipsis too" do
      reduced = css[/@media \(prefers-reduced-motion: reduce\) \{\s*\.pito-achievement-track__dot--reached[^}]*\}/m]
      expect(reduced).to be_present
      expect(reduced).to include(".pito-achievement-track__ellipsis--reached")
    end
  end
end
