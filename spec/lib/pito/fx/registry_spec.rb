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
  #
  # SYNTHETIC — this fixture exercises the SCHEMA, never the shipped ontology
  # (that has its own describe block at the bottom of this file). Its `wall`
  # effect is a stand-in for the `many` cardinality: after the 5.0.0 cull no
  # `many` effect ships, but the cardinality is still law in the validator,
  # in THE COMPATIBILITY GUARD and in fx/engine.js's viable(), so it stays
  # under test here rather than rotting untested until someone adds a wall
  # back.
  VALID = <<~YML
    schema_version: 2
    engine: { fps: 30, dpr_cap: 1.0, crossfade_ms: 700, hysteresis_ms: 300, enforcer_alpha: 0.62, butterflies: 4, ring_idle_ms: 8000, cable_push_strength_min: 0.35, cable_push_strength_max: 0.85, cable_push_duration_ms_min: 400, cable_push_duration_ms_max: 1600 }
    effects:
      sky: { engine: canvas, covers: none, needs_float: false, tint_source: fixed, knobs: { drift_scale: 0.5 } }
      plasma: { engine: webgl, covers: none, needs_float: false, tint_source: theme }
      water: { engine: webgl, covers: single, needs_float: true, tint_source: cover }
      wall: { engine: css, covers: many, needs_float: false, tint_source: cover }
    contexts:
      game_detail: { covers: single, pool: [ { effect: water, weight: 3 } ] }
      game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ] }
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
        expect(described_class.effects.keys).to contain_exactly(:sky, :plasma, :water, :wall)
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
        expect(described_class.pool(:game_list)).to eq([ { effect: :wall, weight: 1 } ])
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
        expect(json[:contexts][:game_list]).to eq(covers: "many", pool: [ { effect: :wall, weight: 1 } ])
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
            "game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ] }",
            "game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ], poolx: [] }"
          ),
          /contexts\.game_list: unknown key "poolx" \(did you mean pool\?\)/ ],
      "unknown pool entry key with a hint" =>
        [ VALID.sub(
            "{ effect: wall, weight: 1 }",
            "{ effect: wall, weight: 1, weightx: 2 }"
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
            "game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ] }",
            "game_list: { covers: many, pool: [] }"
          ),
          /contexts\.game_list\.pool must be a non-empty list of \{effect, weight\}/ ],
      "missing pool key" =>
        [ VALID.sub(
            "game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ] }",
            "game_list: { covers: many }"
          ),
          /contexts\.game_list: missing key "pool"/ ],
      "undeclared pool effect" =>
        [ VALID.sub("{ effect: wall, weight: 1 }", "{ effect: wal, weight: 1 }"),
          /contexts\.game_list\.pool\[0\]\.effect "wal" is not a declared effect \(did you mean wall\?\)/ ],
      "non-positive weight" =>
        [ VALID.sub("{ effect: wall, weight: 1 }", "{ effect: wall, weight: 0 }"),
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
        "game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ] }",
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
        "game_detail: { covers: single, pool: [ { effect: wall, weight: 3 } ] }"
      )
      with_registry(yaml) do
        expect { described_class.effects }.to raise_error(
          described_class::Invalid,
          /contexts\.game_detail: effect "wall" needs covers: many but this context carries covers: single — cover-wall moods never render single-entity moments \(owner law\)/
        )
      end
    end

    it "rejects a many-cover effect pooled on a none context" do
      yaml = VALID.sub(
        "ai: { covers: none, pool: [ { effect: plasma, weight: 2 }, { effect: sky, weight: 1 } ] }",
        "ai: { covers: none, pool: [ { effect: wall, weight: 2 }, { effect: sky, weight: 1 } ] }"
      )
      with_registry(yaml) do
        expect { described_class.effects }.to raise_error(
          described_class::Invalid,
          /contexts\.ai: effect "wall" needs covers: many but this context carries covers: none — cover-wall moods need art to wear \(owner law\)/
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
          "game_list: { covers: many, pool: [ { effect: wall, weight: 1 } ] }",
          "game_list: { covers: many, pool: [ { effect: wall, weight: 1 }, { effect: sky, weight: 1 } ] }"
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

    it "threads the sky's perf-tuned sampling knobs (owner-authorized 2026-07-19 CELL/DENSITY cut)" do
      expect(described_class.effects[:sky][:knobs]).to include(
        drift_scale: 0.5, tilt_gain: 3.0, cell: 22, density: 80
      )
    end

    it "keeps the sky's flock and its idle rings (the 5.0.0 cull spares them by name)" do
      expect(described_class.engine).to include(butterflies: 6, ring_idle_ms: 8000)
    end

    # ── THE 5.0.0 CULL (owner ruling 2026-07-26) ─────────────────────────
    # Keep sky, plasma, water. Purge duotone, lens, glow, trails, aurora,
    # globs, cover_wall — YAML entries AND renderer modules.
    CULLED = %i[duotone lens glow trails aurora globs cover_wall].freeze

    it "ships exactly three moods — sky, plasma, water — and no culled mood survives anywhere" do
      expect(described_class.effects.keys).to contain_exactly(:sky, :plasma, :water)

      pooled = described_class.contexts.values.flat_map { |c| c[:pool].map { |e| e[:effect] } }.uniq
      expect(pooled).to match_array(pooled & %i[sky plasma water])
      CULLED.each do |mood|
        expect(described_class.effects).not_to have_key(mood), "#{mood} is still declared in fx.yml"
        expect(pooled).not_to include(mood), "#{mood} is still pooled by a context"
      end
    end

    it "purges the culled renderer modules from app/javascript/fx/renderers" do
      CULLED.each do |mood|
        path = Rails.root.join("app/javascript/fx/renderers/#{mood}.js")
        expect(path).not_to exist, "#{path} survived the cull"
      end
    end

    it "remaps every context: water on single-cover moments, plasma on AI, sky everywhere else" do
      # Single-cover moments wear water and only water.
      expect(described_class.pool(:game_detail).map { |e| e[:effect] }).to eq([ :water ])
      # A vid's art is its LINKED GAME's art, so a vid with no game link
      # resolves to zero covers — water is `covers: single` and turns
      # non-viable, and the sky answers (owner ruling 2026-07-26). The pool
      # spells that second outcome out.
      expect(described_class.pool(:vid_detail).map { |e| e[:effect] }).to eq([ :water, :sky ])
      expect(described_class.effects[:water][:covers]).to eq("single")

      # Analyze twins its show counterpart VERBATIM (owner 2026-07-13).
      expect(described_class.pool(:analyze_game)).to eq(described_class.pool(:game_detail))
      expect(described_class.pool(:analyze_vid)).to eq(described_class.pool(:vid_detail))
      expect(described_class.pool(:analyze_channel)).to eq(described_class.pool(:channel))
      expect(described_class.contexts).not_to have_key(:analyze)

      # The wall is gone: every many-cover context collapses to the sky.
      %i[game_list vid_list channel analyze_channel].each do |ctx|
        expect(described_class.pool(ctx).map { |e| e[:effect] }).to eq([ :sky ]), "#{ctx} is not a sky moment"
      end

      # The AI family wears plasma — both contexts, nothing else.
      expect(described_class.pool(:ai).map { |e| e[:effect] }).to eq([ :plasma ])
      expect(described_class.pool(:ai_game).map { |e| e[:effect] }).to eq([ :plasma ])

      expect(described_class.pool(:default).map { |e| e[:effect] }).to eq([ :sky ])
    end

    it "leaves no context demanding a cardinality nothing can satisfy" do
      # The cull removed the only `many` effect (cover_wall) and every
      # `single` effect but water. A context is unsatisfiable only if EVERY
      # pool entry demands art the context cannot carry — the boot guard
      # already refuses the mismatched shapes, so what is left to prove is
      # that each context still offers at least one compatible entry.
      declared = described_class.effects.transform_values { |e| e[:covers] }
      expect(declared.values).not_to include("many"), "a `many` effect shipped again — no context can carry it"

      described_class.contexts.each do |name, context|
        compatible = context[:pool].map { |e| e[:effect] }.select do |effect|
          declared[effect] == "none" || declared[effect] == context[:covers]
        end
        expect(compatible).not_to be_empty, "contexts.#{name} pools nothing its `covers: #{context[:covers]}` can satisfy"
      end
    end

    # ── CACHEABILITY (F1's DONE gate) ────────────────────────────────────
    # fx/engine.js picks with a per-event seed:
    #   pool.filter(viable) → fnv1a("fx:<eventId>:<context>") % totalWeight
    # and viable() requires a REGISTERED RENDERER (`renderers[name]`), so the
    # set it rolls over is always a subset of what fx/renderers/index.js
    # exports. Once no context offers more than ONE registered renderer, the
    # roll has nothing to roll: the mood is a pure function of (context, does
    # the payload carry art, what the device can run) and never of which
    # event id happened to land. That is what makes a conversation's
    # background fully described by the `data-fx-context` / `data-fx-covers`
    # attributes the L2 scrollback snapshot already stores.
    def registered_renderers
      source = Rails.root.join("app/javascript/fx/renderers/index.js").read
      # Line-anchored: the RENDERER CONTRACT comment at the top of that file
      # quotes `export default {` too, and an unanchored match reads the
      # comment instead of the code.
      source[/^export default \{([^}]*)\}/, 1].to_s.split(",").map { |n| n.strip.to_sym }.reject(&:empty?)
    end

    it "registers exactly the two renderer modules the cull kept" do
      expect(registered_renderers).to contain_exactly(:plasma, :water)
      # `sky` is deliberately NOT a renderer — it is painted by the fx
      # controller's own resting pass, which is why pooling it means "the sky
      # answers" rather than "mount something".
      expect(registered_renderers).not_to include(:sky)
      expect(registered_renderers & CULLED).to be_empty
    end

    it "offers at most one renderable mood per context, so the per-event seed decides nothing" do
      registered = registered_renderers
      described_class.contexts.each do |name, context|
        effects = context[:pool].map { |e| e[:effect] }
        renderable = effects & registered
        expect(renderable.size).to be <= 1,
          "contexts.#{name} can roll #{renderable.inspect} — the mood would vary per event id"
        # Anything that is not renderable must be the deliberate sky marker,
        # never a mood that quietly stopped existing.
        expect(effects - registered).to match_array((effects - registered) & [ :sky ])
      end
    end

    it "threads a declared effect for every pooled name (no dangling references)" do
      described_class.contexts.each_value do |context|
        context[:pool].each do |entry|
          expect(described_class.effects).to have_key(entry[:effect])
        end
      end
    end
  end
end
