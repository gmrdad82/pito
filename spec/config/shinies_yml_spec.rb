# frozen_string_literal: true

require "rails_helper"

# ── The shinies.yml schema-integrity suite ──────────────────────────────────
#
# The owner's foundation for config/pito/shinies.yml — the achievements
# ontology every install inherits as its shipped defaults (self-hosters mount
# their own copy over it; see the file's own header comment). This guard
# exercises the REAL shipped file through the REAL loader
# (Pito::Achievements::Config) and the REAL ladder/material logic
# (Pito::Achievement::Tier) — no stubbing — so a future edit to the yml (a new
# metric, a re-shaped ceiling, an award threshold) is proven sound before it
# ships. Mirrors the tone/shape of spec/dispatch/schema_integrity_spec.rb
# (tools.yml's own guard) and spec/config/recurring_yml_spec.rb.
#
#   1. LOAD      — the file parses through the real loader without raising.
#   2. SCOPES    — coverage is exactly Video/Game/Channel; metrics are
#                  non-empty and known; house semantics (subs vs subs_gained).
#   3. LADDERS   — every ceiling anchors a real 1-2-5 stone ladder; awards
#                  ascend, strictly above the channel-subs stone ceiling.
#   4. MATERIALS — opal crowns every stone ladder; metals land exactly on the
#                  award thresholds.
#   5. DRIFT     — Evaluate.metrics_for (what the refresh pipeline feeds)
#                  agrees with Config.metrics_for (what the yml declares) for
#                  real Channel/Video/Game instances.
RSpec.describe "config/pito/shinies.yml schema integrity" do
  # Reload from disk once — the same frozen document the app runs on.
  Pito::Achievements::Config.reload!
  CONFIG   = Pito::Achievements::Config
  TIER     = Pito::Achievement::Tier
  CEILINGS = CONFIG.ceilings
  AWARDS   = CONFIG.awards

  # Flattened { scope:, metric:, ceiling: } rows for table-driven ladder specs.
  CEILING_ROWS = CEILINGS.flat_map do |scope, metrics|
    metrics.map { |metric, ceiling| { scope:, metric:, ceiling: } }
  end.freeze

  # ══ LAYER 1 — LOAD ═══════════════════════════════════════════════════════
  describe "LOAD — the real file parses through the real loader" do
    it "loads without raising" do
      expect { Pito::Achievements::Config.reload! }.not_to raise_error
      expect(Pito::Achievements::Config.data).to be_a(Hash)
    end

    it "declares a schema_version the loader supports" do
      raw = YAML.safe_load_file(Pito::Achievements::Config::PATH, symbolize_names: true)
      expect(Pito::Achievements::Config::SUPPORTED_SCHEMA_VERSIONS).to include(raw[:schema_version])
    end
  end

  # ══ LAYER 2 — SCOPES & METRICS ═══════════════════════════════════════════
  describe "SCOPES — coverage is exactly the domain triad" do
    it "covers Video, Game, and Channel — no more, no less" do
      expect(CEILINGS.keys).to contain_exactly("Video", "Game", "Channel")
    end

    CEILINGS.each do |scope, metrics|
      it "#{scope} lists at least one metric, all within KNOWN_METRICS" do
        expect(metrics.keys).not_to be_empty
        expect(metrics.keys - Pito::Achievements::Config::KNOWN_METRICS).to eq([])
      end
    end

    it "Channel carries subs, never subs_gained (a channel counts its TOTAL)" do
      expect(CONFIG.metrics_for("Channel")).to include("subs")
      expect(CONFIG.metrics_for("Channel")).not_to include("subs_gained")
    end

    it "Video carries subs_gained, never subs (vids count subs GAINED)" do
      expect(CONFIG.metrics_for("Video")).to include("subs_gained")
      expect(CONFIG.metrics_for("Video")).not_to include("subs")
    end

    it "Game carries subs_gained, never subs (games count subs GAINED)" do
      expect(CONFIG.metrics_for("Game")).to include("subs_gained")
      expect(CONFIG.metrics_for("Game")).not_to include("subs")
    end
  end

  # ══ LAYER 3 — LADDERS ═════════════════════════════════════════════════════
  describe "LADDERS — every ceiling anchors a real 1-2-5 stone series" do
    CEILING_ROWS.each do |row|
      it "#{row[:scope]} #{row[:metric]} climbs a non-empty ladder topping out at #{row[:ceiling]}" do
        series = TIER.series_for(scope: row[:scope], metric: row[:metric])
        expect(series).not_to be_empty

        # Only channel subs appends the award track after the stone
        # ceiling — strip those out (by track, not by numeric coincidence;
        # a stone ceiling can otherwise collide with an award value) before
        # checking where the STONE ladder tops out.
        stone_series = TIER.award_track?(row[:scope], row[:metric]) ? series.reject { |t| AWARDS.key?(t) } : series
        expect(stone_series).to include(row[:ceiling])
        expect(stone_series.last).to eq(row[:ceiling])
      end
    end
  end

  describe "AWARDS — ascend, strictly above the channel-subs stone ceiling" do
    it "ascends" do
      expect(AWARDS.keys).to eq(AWARDS.keys.sort)
    end

    it "every award threshold sits strictly above the channel-subs ceiling" do
      channel_subs_ceiling = CEILINGS.fetch("Channel").fetch("subs")
      expect(AWARDS.keys).to all(be > channel_subs_ceiling)
    end
  end

  # ══ LAYER 4 — MATERIALS ═══════════════════════════════════════════════════
  describe "MATERIALS — opal crowns every ladder, metals land on the awards" do
    CEILING_ROWS.each do |row|
      it "#{row[:scope]} #{row[:metric]} tops out in opal at #{row[:ceiling]}" do
        material = TIER.material_for(scope: row[:scope], metric: row[:metric], threshold: row[:ceiling])
        expect(material).to eq(Pito::Achievement::Tier::STONES.last)
      end
    end

    AWARDS.each do |threshold, metal|
      it "channel subs at #{threshold} is #{metal}, not a stone" do
        material = TIER.material_for(scope: "Channel", metric: "subs", threshold:)
        expect(material).to eq(metal)
        expect(Pito::Achievement::Tier::STONES).not_to include(material)
      end
    end
  end

  # ══ LAYER 5 — DRIFT ═══════════════════════════════════════════════════════
  describe "DRIFT — Evaluate.metrics_for agrees with Config.metrics_for" do
    it "Channel: the evaluator and the config declare the same metric set" do
      channel = build_stubbed(:channel)
      expect(Pito::Achievements::Evaluate.metrics_for(channel)).to eq(CONFIG.metrics_for("Channel"))
    end

    it "Video: the evaluator and the config declare the same metric set" do
      video = build_stubbed(:video)
      expect(Pito::Achievements::Evaluate.metrics_for(video)).to eq(CONFIG.metrics_for("Video"))
    end

    it "Game: the evaluator and the config declare the same metric set" do
      game = build_stubbed(:game)
      expect(Pito::Achievements::Evaluate.metrics_for(game)).to eq(CONFIG.metrics_for("Game"))
    end
  end
end
