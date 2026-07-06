# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::SegmentSelection do
  # Default to verb: :show, entity: :game (5-segment table, richest coverage).
  def parse(raw, verb: :show, entity: :game)
    described_class.parse(raw, verb: verb, entity: entity)
  end

  let(:all_game_names) { %w[detail similar videos channels at-a-glance] }

  # ── :default mode (bare command) ─────────────────────────────────────────────

  describe "bare command (no introducer)" do
    let(:result) { parse("show game #3") }

    it "returns mode :default" do
      expect(result.mode).to eq(:default)
    end

    it "returns only the default segment name (detail)" do
      expect(result.names).to eq(%w[detail])
    end

    it "returns no unknown tokens" do
      expect(result.unknown).to eq([])
    end

    it "returns no conflict" do
      expect(result.conflict).to be(false)
    end
  end

  # ── :full mode ────────────────────────────────────────────────────────────────

  describe "'full' introducer" do
    let(:result) { parse("show game #3 full") }

    it "returns mode :full" do
      expect(result.mode).to eq(:full)
    end

    it "returns all five segment names in table order" do
      expect(result.names).to eq(all_game_names)
    end

    it "returns no unknown tokens" do
      expect(result.unknown).to eq([])
    end

    it "returns no conflict" do
      expect(result.conflict).to be(false)
    end
  end

  # ── :with mode ────────────────────────────────────────────────────────────────

  describe "'with' introducer" do
    it "'with at-a-glance' returns mode :with and [detail, at-a-glance] in table order" do
      result = parse("show game #3 with at-a-glance")
      expect(result.mode).to eq(:with)
      expect(result.names).to eq(%w[detail at-a-glance])
    end

    it "'with similar, channels' (comma+space) includes detail+similar+channels in table order" do
      result = parse("show game #3 with similar, channels")
      expect(result.mode).to eq(:with)
      expect(result.names).to eq(%w[detail similar channels])
    end

    it "produces no conflict when only 'with' is present" do
      expect(parse("show game #3 with similar").conflict).to be(false)
    end

    it "already-default segment in the 'with' list does not produce a duplicate" do
      result = parse("show game #3 with detail")
      expect(result.names).to eq(%w[detail])
    end
  end

  # ── :only mode ────────────────────────────────────────────────────────────────

  describe "'only' introducer" do
    it "'only channels,similar' returns names in TABLE order (similar before channels)" do
      result = parse("show game #3 only channels,similar")
      expect(result.mode).to eq(:only)
      expect(result.names).to eq(%w[similar channels])
    end

    it "'only similar' excludes all other segments" do
      result = parse("show game #3 only similar")
      expect(result.names).to eq(%w[similar])
    end

    it "produces no conflict when only 'only' is present" do
      expect(parse("show game #3 only similar").conflict).to be(false)
    end
  end

  # ── case-insensitivity ────────────────────────────────────────────────────────

  describe "case-insensitivity" do
    it "ONLY AT-A-GLANCE uppercased parses correctly" do
      result = parse("show game #3 ONLY AT-A-GLANCE")
      expect(result.mode).to eq(:only)
      expect(result.names).to eq(%w[at-a-glance])
    end

    it "FULL uppercased parses correctly" do
      result = parse("show game #3 FULL")
      expect(result.mode).to eq(:full)
      expect(result.names).to eq(all_game_names)
    end

    it "WITH SIMILAR uppercased parses correctly" do
      result = parse("show game #3 WITH SIMILAR")
      expect(result.mode).to eq(:with)
      expect(result.names).to eq(%w[detail similar])
    end
  end

  # ── unknown tokens ────────────────────────────────────────────────────────────

  describe "unknown tokens" do
    it "unrecognised token lands in unknown; valid tokens still parse" do
      result = parse("show game #3 with similar, bogus-thing")
      expect(result.unknown).to eq(%w[bogus-thing])
      expect(result.names).to include("similar")
    end

    it "all-unknown token list produces empty names and captures every unknown" do
      result = parse("show game #3 only nope,also-nope")
      expect(result.names).to eq([])
      expect(result.unknown).to eq(%w[nope also-nope])
    end
  end

  # ── conflict detection ────────────────────────────────────────────────────────

  describe "conflict detection" do
    it "'full with detail' sets conflict: true and mode :with (with wins over full)" do
      result = parse("show game #3 full with detail")
      expect(result.conflict).to be(true)
      expect(result.mode).to eq(:with)
    end
  end

  # ── duplicate token deduplication ────────────────────────────────────────────

  describe "duplicate token deduplication" do
    it "'with similar,similar' produces a single similar in names" do
      result = parse("show game #3 with similar,similar")
      expect(result.names).to eq(%w[detail similar])
    end
  end

  # ── trailing introducer with no token list ────────────────────────────────────

  describe "trailing 'with' with no following tokens" do
    it "falls back to :default mode without crashing (WITH_RE requires following content)" do
      result = parse("show game #3 with")
      expect(result.mode).to eq(:default)
      expect(result.names).to eq(%w[detail])
    end
  end

  # ── extra_vocabulary pass-through (analyze verb) ─────────────────────────────
  # Metric tokens appear in the same raw string as segment tokens; they must not
  # land in +unknown+ when extra_vocabulary is supplied.

  describe "extra_vocabulary pass-through (verb: :analyze)" do
    let(:metric_vocab) do
      Pito::Analytics::MetricSelection::ALIASES.keys +
        Pito::Analytics::MetricOrder::METRICS.keys.map(&:to_s)
    end

    def analyze_parse(raw)
      described_class.parse(raw, verb: :analyze, entity: :vid, extra_vocabulary: metric_vocab)
    end

    it "metric token alone in 'with' list is not reported as unknown" do
      result = analyze_parse("analyze vid #1 with views")
      expect(result.unknown).to eq([])
    end

    it "metric token alone in 'with' yields mode :with and default segment names" do
      result = analyze_parse("analyze vid #1 with views")
      expect(result.mode).to eq(:with)
      expect(result.names).to eq(%w[numbers])
    end

    it "'with views,breakdowns' yields names [numbers, breakdowns] and no unknown" do
      result = analyze_parse("analyze vid #1 with views,breakdowns")
      expect(result.mode).to eq(:with)
      expect(result.names).to eq(%w[numbers breakdowns])
      expect(result.unknown).to eq([])
    end

    it "alias token (e.g. 'comms') is not reported as unknown" do
      result = analyze_parse("analyze vid #1 with comms")
      expect(result.unknown).to eq([])
      expect(result.names).to eq(%w[numbers])
    end

    it "genuine garbage is still captured as unknown even when extra_vocabulary is supplied" do
      result = analyze_parse("analyze vid #1 with bogus-garbage")
      expect(result.unknown).to eq(%w[bogus-garbage])
    end

    it "mixed clause: metric token + segment + garbage → segment in names, garbage in unknown" do
      result = analyze_parse("analyze vid #1 with views,breakdowns,rubbish")
      expect(result.names).to eq(%w[numbers breakdowns])
      expect(result.unknown).to eq(%w[rubbish])
    end

    it "without extra_vocabulary, metric tokens land in unknown as before" do
      result = described_class.parse("analyze vid #1 with views", verb: :analyze, entity: :vid)
      expect(result.unknown).to eq(%w[views])
    end
  end

  # ── entity: :channel coverage ─────────────────────────────────────────────────

  describe "entity: :channel" do
    it "full returns all channel segment names in table order" do
      result = described_class.parse("show channel full", verb: :show, entity: :channel)
      expect(result.names).to eq(%w[detail games videos at-a-glance])
    end

    it "bare command returns default names (detail only)" do
      result = described_class.parse("show channel @handle", verb: :show, entity: :channel)
      expect(result.names).to eq(%w[detail])
    end
  end

  # ── segment aliases ───────────────────────────────────────────────────────────
  # "similars" is declared as an alias for "similar" on show/game.
  # Aliased tokens must land in names as the CANONICAL name and never in unknown.

  describe "segment aliases (show/game — similars → similar)" do
    it "'with similars' resolves to the canonical 'similar' in names" do
      result = parse("show game #3 with similars")
      expect(result.mode).to eq(:with)
      expect(result.names).to include("similar")
      expect(result.unknown).to eq([])
    end

    it "'only similars' resolves names to ['similar'] (table order)" do
      result = parse("show game #3 only similars")
      expect(result.mode).to eq(:only)
      expect(result.names).to eq(%w[similar])
      expect(result.unknown).to eq([])
    end

    it "alias and canonical in the same list deduplicates to one 'similar' entry" do
      result = parse("show game #3 with similar,similars")
      expect(result.names.count("similar")).to eq(1)
    end

    it "an unknown token is still reported as unknown even alongside a valid alias" do
      result = parse("show game #3 with similars,bogus")
      expect(result.names).to include("similar")
      expect(result.unknown).to eq(%w[bogus])
    end

    it "'with similars,channels' includes both (default detail + similar + channels in table order)" do
      result = parse("show game #3 with similars,channels")
      expect(result.mode).to eq(:with)
      expect(result.names).to eq(%w[detail similar channels])
    end
  end

  # ── entity: :vid coverage ─────────────────────────────────────────────────────

  describe "entity: :vid" do
    it "full returns all vid segment names in table order" do
      result = described_class.parse("show vid full", verb: :show, entity: :vid)
      expect(result.names).to eq(%w[detail game at-a-glance])
    end

    it "bare command returns default names (detail only)" do
      result = described_class.parse("show vid #1", verb: :show, entity: :vid)
      expect(result.names).to eq(%w[detail])
    end
  end

  # ── :without mode ─────────────────────────────────────────────────────────────

  describe "'without' introducer" do
    it "'without channels' returns mode :without and all_game_names minus channels" do
      result = parse("show game #3 without channels")
      expect(result.mode).to eq(:without)
      expect(result.names).to eq(%w[detail similar videos at-a-glance])
    end

    it "'without at-a-glance,similar' returns detail + videos + channels in table order" do
      result = parse("show game #3 without at-a-glance,similar")
      expect(result.mode).to eq(:without)
      expect(result.names).to eq(%w[detail videos channels])
    end

    it "'without detail' removes only detail from all names" do
      result = parse("show game #3 without detail")
      expect(result.names).to eq(%w[similar videos channels at-a-glance])
    end

    it "produces no conflict when only 'without' is present" do
      expect(parse("show game #3 without similar").conflict).to be(false)
    end

    it "'without similars' (alias) resolves canonical 'similar' and excludes it" do
      result = parse("show game #3 without similars")
      expect(result.names).not_to include("similar")
      expect(result.unknown).to eq([])
    end

    it "'without' with all segments named returns empty names" do
      result = parse("show game #3 without detail,similar,videos,channels,at-a-glance")
      expect(result.names).to eq([])
    end

    it "unknown token in 'without' list lands in unknown" do
      result = parse("show game #3 without channels,bogus")
      expect(result.unknown).to eq(%w[bogus])
      expect(result.names).not_to include("channels")
    end
  end

  # ── extra_vocabulary pass-through for :without (analyze verb) ─────────────────

  describe "extra_vocabulary pass-through with 'without' introducer (verb: :analyze)" do
    let(:metric_vocab) do
      Pito::Analytics::MetricSelection::ALIASES.keys +
        Pito::Analytics::MetricOrder::METRICS.keys.map(&:to_s)
    end

    def analyze_parse(raw)
      described_class.parse(raw, verb: :analyze, entity: :vid, extra_vocabulary: metric_vocab)
    end

    it "'without breakdowns' returns mode :without and names [numbers]" do
      result = analyze_parse("analyze vid #1 without breakdowns")
      expect(result.mode).to eq(:without)
      expect(result.names).to eq(%w[numbers])
    end

    it "'without comments' (metric token) is silently skipped — names = all analyze segments [numbers, breakdowns]" do
      result = analyze_parse("analyze vid #1 without comments")
      expect(result.mode).to eq(:without)
      expect(result.names).to eq(%w[numbers breakdowns])
      expect(result.unknown).to eq([])
    end

    it "metric token in 'without' list is not reported as unknown" do
      result = analyze_parse("analyze vid #1 without views")
      expect(result.unknown).to eq([])
    end
  end

  # ── 'without' does not interfere with 'with' boundary ─────────────────────────

  describe "\\bwith\\b boundary — 'without' does NOT trigger WITH_RE" do
    it "a raw string containing only 'without' does not set mode :with" do
      result = parse("show game #3 without similar")
      expect(result.mode).to eq(:without)
      expect(result.mode).not_to eq(:with)
    end

    it "WITH_RE does not match inside the word 'without' (word-boundary proof)" do
      expect("without similar").not_to match(Pito::Chat::SegmentSelection::WITH_RE)
    end

    it "'with X without Y' is a conflict (both introducers present)" do
      result = parse("show game #3 with detail without similar")
      expect(result.conflict).to be(true)
    end
  end

  # ── strip removes without-clauses ─────────────────────────────────────────────

  describe "strip removes 'without' clauses" do
    it "strips a trailing without-clause" do
      expect(described_class.strip("show game #3 without channels")).to eq("show game #3")
    end

    it "strips without-clause alongside with-clause (both removed for independent parsing)" do
      stripped = described_class.strip("show game #3 with detail without channels")
      expect(stripped).not_to include("without")
      expect(stripped).not_to include("with detail")
    end
  end
end
