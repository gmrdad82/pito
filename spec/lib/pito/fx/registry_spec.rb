# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Fx::Registry do
  after { described_class.reload! }

  # Write +yaml+ to a temp file and point the registry at it for one example.
  def with_registry(yaml)
    Tempfile.create([ "fx", ".yml" ]) do |f|
      f.write(yaml)
      f.flush
      stub_const("Pito::Fx::Registry::PATH", Pathname.new(f.path))
      described_class.reload!
      yield
    end
  end

  # schema_version 2: effects declare `covers:` (single|many|none) instead of
  # the old boolean `needs_cover`; contexts are {covers:, pool:} maps, not
  # bare arrays.
  VALID = <<~YML
    schema_version: 2
    engine: { fps: 30, dpr_cap: 1.0, crossfade_ms: 700, hysteresis_ms: 300, enforcer_alpha: 0.62, butterflies: 4, ring_idle_ms: 8000 }
    effects:
      sky: { engine: canvas, covers: none, needs_float: false, tint_source: fixed, knobs: { drift_scale: 0.5 } }
      plasma: { engine: webgl, covers: none, needs_float: false, tint_source: theme }
      water: { engine: webgl, covers: single, needs_float: true, tint_source: cover }
      cover_wall: { engine: css, covers: many, needs_float: false, tint_source: cover }
    contexts:
      game_detail: { covers: single, pool: [ { effect: water, weight: 3 } ] }
      game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ] }
      ai: { covers: none, pool: [ { effect: plasma, weight: 2 }, { effect: sky, weight: 1 } ] }
      default: { covers: none, pool: [ { effect: sky, weight: 1 } ] }
  YML

  describe "a valid config" do
    it "exposes engine, effects, and contexts as frozen structures" do
      with_registry(VALID) do
        expect(described_class.engine).to include(
          fps: 30, dpr_cap: 1.0, crossfade_ms: 700, hysteresis_ms: 300,
          enforcer_alpha: 0.62, butterflies: 4, ring_idle_ms: 8000
        )
        expect(described_class.effects.keys).to contain_exactly(:sky, :plasma, :water, :cover_wall)
        expect(described_class.contexts.keys).to contain_exactly(:game_detail, :game_list, :ai, :default)

        expect(described_class.engine).to be_frozen
        expect(described_class.effects).to be_frozen
        expect(described_class.effects[:water]).to be_frozen
        expect(described_class.contexts).to be_frozen
        expect(described_class.contexts[:game_detail]).to be_frozen
        expect(described_class.pool(:game_detail)).to be_frozen
        expect(described_class.pool(:game_detail).first).to be_frozen
      end
    end

    it "returns the weighted pool array for a known context" do
      with_registry(VALID) do
        expect(described_class.pool(:game_detail)).to eq([ { effect: :water, weight: 3 } ])
        expect(described_class.pool(:game_list)).to eq([ { effect: :cover_wall, weight: 1 } ])
      end
    end

    it "falls back to the default pool for an unknown context" do
      with_registry(VALID) do
        expect(described_class.pool(:no_such_context)).to eq(described_class.pool(:default))
      end
    end

    it "serializes context maps as {covers:, pool:} for the JS engine" do
      with_registry(VALID) do
        json = described_class.as_json
        expect(json.keys).to contain_exactly(:engine, :effects, :contexts)
        expect(json[:contexts][:game_detail]).to eq(covers: "single", pool: [ { effect: :water, weight: 3 } ])
        expect(json[:contexts][:game_list]).to eq(covers: "many", pool: [ { effect: :cover_wall, weight: 1 } ])
      end
    end
  end

  describe "validation" do
    {
      "wrong schema_version" =>
        [ VALID.sub("schema_version: 2", "schema_version: 9"),
          /schema_version 9 unsupported \(expected 2\)/ ],
      "unknown top-level key with a hint" =>
        [ VALID.sub("schema_version: 2\n", "schema_version: 2\ncontext: {}\n"),
          /unknown top-level key "context" \(did you mean contexts\?\)/ ],
      "unknown engine key with a hint" =>
        [ VALID.sub("fps: 30,", "fps: 30, fpss: 60,"),
          /engine: unknown key "fpss" \(did you mean fps\?\)/ ],
      "unknown effect key with a hint" =>
        [ VALID.sub(
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover }",
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover, tintsource: theme }"
          ),
          /effects\.water: unknown key "tintsource" \(did you mean tint_source\?\)/ ],
      "unknown context key with a hint" =>
        [ VALID.sub(
            "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ] }",
            "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ], poolx: [] }"
          ),
          /contexts\.game_list: unknown key "poolx" \(did you mean pool\?\)/ ],
      "unknown pool entry key with a hint" =>
        [ VALID.sub(
            "{ effect: cover_wall, weight: 1 }",
            "{ effect: cover_wall, weight: 1, weightx: 2 }"
          ),
          /contexts\.game_list\.pool\[0\]: unknown key "weightx" \(did you mean weight\?\)/ ],
      "missing engine key" =>
        [ VALID.sub(", ring_idle_ms: 8000", ""),
          /engine\.ring_idle_ms must be a positive number \(got nil\)/ ],
      "missing effect required key" =>
        [ VALID.sub(
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover }",
            "water: { engine: webgl, covers: single, needs_float: true }"
          ),
          /effects\.water: missing key "tint_source"/ ],
      "a lingering needs_cover key" =>
        [ VALID.sub(
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover }",
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover, needs_cover: false }"
          ),
          /effects\.water: needs_cover is gone — declare `covers:` \(single\|many\|none\) instead/ ],
      "bad engine enum" =>
        [ VALID.sub("water: { engine: webgl,", "water: { engine: webgpu,"),
          /effects\.water\.engine "webgpu" unknown \(did you mean webgl\?\) \(allowed: css, canvas, webgl\)/ ],
      "bad covers enum" =>
        [ VALID.sub("water: { engine: webgl, covers: single,", "water: { engine: webgl, covers: singlee,"),
          /effects\.water\.covers "singlee" unknown \(did you mean single\?\) \(allowed: single, many, none\)/ ],
      "bad tint_source enum" =>
        [ VALID.sub(
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover }",
            "water: { engine: webgl, covers: single, needs_float: true, tint_source: cover_art }"
          ),
          /effects\.water\.tint_source "cover_art" unknown \(did you mean cover\?\) \(allowed: theme, cover, fixed\)/ ],
      "non-boolean needs_float" =>
        [ VALID.sub(
            "water: { engine: webgl, covers: single, needs_float: true,",
            "water: { engine: webgl, covers: single, needs_float: maybe,"
          ),
          /effects\.water\.needs_float must be true or false \(got "maybe"\)/ ],
      "non-numeric knob" =>
        [ VALID.sub("drift_scale: 0.5", "drift_scale: fast"),
          /effects\.sky\.knobs\.drift_scale must be a number \(got "fast"\)/ ],
      "empty pool" =>
        [ VALID.sub(
            "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ] }",
            "game_list: { covers: many, pool: [] }"
          ),
          /contexts\.game_list\.pool must be a non-empty list of \{effect, weight\}/ ],
      "missing pool key" =>
        [ VALID.sub(
            "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ] }",
            "game_list: { covers: many }"
          ),
          /contexts\.game_list: missing key "pool"/ ],
      "undeclared pool effect" =>
        [ VALID.sub("{ effect: cover_wall, weight: 1 }", "{ effect: cover_wal, weight: 1 }"),
          /contexts\.game_list\.pool\[0\]\.effect "cover_wal" is not a declared effect \(did you mean cover_wall\?\)/ ],
      "non-positive weight" =>
        [ VALID.sub("{ effect: cover_wall, weight: 1 }", "{ effect: cover_wall, weight: 0 }"),
          /contexts\.game_list\.pool\[0\]\.weight must be a positive number \(got 0\)/ ],
      "missing default context" =>
        [ VALID.sub("\n  default: { covers: none, pool: [ { effect: sky, weight: 1 } ] }", ""),
          /contexts must declare `default` \(the sky fallback\)/ ]
    }.each do |name, (yaml, matcher)|
      it "rejects #{name}" do
        with_registry(yaml) do
          expect { described_class.effects }.to raise_error(described_class::Invalid, matcher)
        end
      end
    end
  end

  describe "THE COMPATIBILITY GUARD (owner law)" do
    it "rejects a single-cover effect pooled on a many context" do
      yaml = VALID.sub(
        "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ] }",
        "game_list: { covers: many, pool: [ { effect: water, weight: 1 } ] }"
      )
      with_registry(yaml) do
        expect { described_class.effects }.to raise_error(
          described_class::Invalid,
          /contexts\.game_list: effect "water" needs covers: single but this context carries covers: many — single-cover moods never render lists \(owner law\)/
        )
      end
    end

    it "rejects a single-cover effect pooled on a none context" do
      yaml = VALID.sub(
        "ai: { covers: none, pool: [ { effect: plasma, weight: 2 }, { effect: sky, weight: 1 } ] }",
        "ai: { covers: none, pool: [ { effect: water, weight: 2 }, { effect: sky, weight: 1 } ] }"
      )
      with_registry(yaml) do
        expect { described_class.effects }.to raise_error(
          described_class::Invalid,
          /contexts\.ai: effect "water" needs covers: single but this context carries covers: none — single-cover moods need art to wear \(owner law\)/
        )
      end
    end

    it "rejects a many-cover effect pooled on a single context" do
      yaml = VALID.sub(
        "game_detail: { covers: single, pool: [ { effect: water, weight: 3 } ] }",
        "game_detail: { covers: single, pool: [ { effect: cover_wall, weight: 3 } ] }"
      )
      with_registry(yaml) do
        expect { described_class.effects }.to raise_error(
          described_class::Invalid,
          /contexts\.game_detail: effect "cover_wall" needs covers: many but this context carries covers: single — cover-wall moods never render single-entity moments \(owner law\)/
        )
      end
    end

    it "rejects a many-cover effect pooled on a none context" do
      yaml = VALID.sub(
        "ai: { covers: none, pool: [ { effect: plasma, weight: 2 }, { effect: sky, weight: 1 } ] }",
        "ai: { covers: none, pool: [ { effect: cover_wall, weight: 2 }, { effect: sky, weight: 1 } ] }"
      )
      with_registry(yaml) do
        expect { described_class.effects }.to raise_error(
          described_class::Invalid,
          /contexts\.ai: effect "cover_wall" needs covers: many but this context carries covers: none — cover-wall moods need art to wear \(owner law\)/
        )
      end
    end

    it "allows a covers: none effect in single, many, and none contexts alike" do
      yaml = VALID
        .sub(
          "game_detail: { covers: single, pool: [ { effect: water, weight: 3 } ] }",
          "game_detail: { covers: single, pool: [ { effect: water, weight: 3 }, { effect: sky, weight: 1 } ] }"
        )
        .sub(
          "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 } ] }",
          "game_list: { covers: many, pool: [ { effect: cover_wall, weight: 1 }, { effect: sky, weight: 1 } ] }"
        )

      with_registry(yaml) do
        expect { described_class.effects }.not_to raise_error
        expect(described_class.pool(:game_detail).map { |e| e[:effect] }).to include(:sky)
        expect(described_class.pool(:game_list).map { |e| e[:effect] }).to include(:sky)
        expect(described_class.pool(:ai).map { |e| e[:effect] }).to include(:sky)
      end
    end
  end

  describe "add-an-effect proof" do
    it "sees a brand-new effect and context with ZERO Ruby edits" do
      extended = VALID
        .sub("effects:", "effects:\n  bokeh: { engine: canvas, covers: none, needs_float: false, tint_source: fixed }")
        .sub("contexts:", "contexts:\n  vid: { covers: none, pool: [ { effect: bokeh, weight: 1 } ] }")

      with_registry(extended) do
        expect(described_class.effects[:bokeh]).to include(engine: "canvas", covers: "none")
        expect(described_class.pool(:vid).first[:effect]).to eq(:bokeh)
        expect(described_class.as_json[:effects]).to have_key(:bokeh)
      end
    end
  end

  describe "reload!" do
    it "memoizes until reload!, then re-reads the file" do
      Tempfile.create([ "fx", ".yml" ]) do |f|
        f.write(VALID)
        f.flush
        stub_const("Pito::Fx::Registry::PATH", Pathname.new(f.path))
        described_class.reload!
        expect(described_class.contexts).not_to have_key(:vid)

        f.rewind
        f.write(VALID.sub("contexts:", "contexts:\n  vid: { covers: none, pool: [ { effect: sky, weight: 1 } ] }"))
        f.flush
        expect(described_class.contexts).not_to have_key(:vid) # memoized

        described_class.reload!
        expect(described_class.contexts).to have_key(:vid) # re-read
      end
    end
  end

  describe "the shipped config" do
    before { described_class.reload! }

    it "loads config/pito/fx.yml without raising" do
      expect { described_class.reload! }.not_to raise_error
      expect(described_class.effects).to be_frozen
    end

    it "pins the owner placement law: locked single-cover moods + glow; walls 50/50 with plasma" do
      # The single-cover family: the locked trio + glow (owner verdict sheet,
      # 2026-07-13) — and nothing wall-ish or cover-less-only.
      expect(described_class.pool(:game_detail).map { |e| e[:effect] }).to contain_exactly(:duotone, :water, :lens)
      # The wall contexts: cover_wall and plasma at EQUAL weight — plasma is
      # both the 50/50 partner and the thin-shelf fallback (under the wall's
      # min_covers the pool degrades to plasma, never to a bare sky).
      %i[game_list vid_list channel].each do |ctx|
        pool = described_class.pool(ctx)
        # 50/50 (owner): the wall and plasma, equal weight, nothing else.
        expect(pool.map { |e| e[:effect] }).to contain_exactly(:cover_wall, :plasma)
        expect(pool.map { |e| e[:weight] }.uniq).to eq([ 1 ])
      end
      # Plasma serves WALLS wherever they hang — the three list/channel
      # contexts and analyze_channel, which twins show channel (owner
      # 2026-07-13) — and nowhere else.
      plasma_homes = described_class.contexts.select { |_, c| c[:pool].any? { |e| e[:effect] == :plasma } }.keys
      expect(plasma_homes).to contain_exactly(:game_list, :vid_list, :channel, :analyze_channel)
      # Aurora lives EXCLUSIVELY in ai (owner 2026-07-13); analyze_game/vid
      # twin their show counterparts verbatim; bare analyze has no entry —
      # breakdowns get the sky.
      aurora_homes = described_class.contexts.select { |_, c| c[:pool].any? { |e| e[:effect] == :aurora } }.keys
      expect(aurora_homes).to contain_exactly(:ai)
      # GLOW is exclusive to game-linked AI answers (owner 2026-07-13) —
      # nowhere else, and ai_game wears nothing else.
      glow_homes = described_class.contexts.select { |_, c| c[:pool].any? { |e| e[:effect] == :glow } }.keys
      expect(glow_homes).to contain_exactly(:ai_game)
      expect(described_class.pool(:ai_game).map { |e| e[:effect] }).to eq([ :glow ])
      expect(described_class.pool(:analyze_game)).to eq(described_class.pool(:game_detail))
      expect(described_class.pool(:analyze_vid)).to eq(described_class.pool(:vid_detail))
      expect(described_class.pool(:analyze_channel)).to eq(described_class.pool(:channel))
      expect(described_class.contexts).not_to have_key(:analyze)
      # AI wears the globs, the ring-cascade trails, and the aurora —
      # nothing else (owner 2026-07-13; plasma is walls-only).
      expect(described_class.pool(:ai).map { |e| e[:effect] }).to contain_exactly(:globs, :trails, :aurora)
    end
  end
end
