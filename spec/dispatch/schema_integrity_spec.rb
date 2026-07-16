# frozen_string_literal: true

require "rails_helper"

# ── The tools.yml schema-integrity suite (plan-0.9.5 TS) ────────────────────────
#
# The owner's foundation: EVERY option in config/pito/tools.yml is specced for
# accuracy, resolution, and output so future tools/options can be added on solid
# ground. Three layers, each a failure-reporter for the future tool author:
#
#   1. STRUCTURE  — the whole file is well-formed per Pito::Dispatch::Schema
#                   (allowed keys, value types, enums; unknown keys rejected);
#                   no alias collides across a dispatch namespace.
#   2. RESOLUTION — every reference resolves: builder/fill/dispatch constants,
#                   copy keys, reply targets, slot vocabularies, and the segment
#                   table matches Pito::Chat::Segments exactly.
#   3. OUTPUT     — the Pito::Dispatch::Config read contracts are pinned.
#
# No DB, no handler execution — pure config + constant + i18n resolution.
RSpec.describe "tools.yml schema integrity", type: :dispatch do
  # Load the real, frozen document once — the same structure the app dispatches on.
  Pito::Dispatch::Config.reload!
  DOC   = Pito::Dispatch::Config.data
  TOOLS = DOC[:tools]

  # Every structural violation in the real file, computed once (expected: none).
  STRUCTURAL_ERRORS = Pito::Dispatch::Schema.validate(DOC)

  # Flattened rows for table-driven resolution specs.
  SEGMENT_ROWS = TOOLS.flat_map do |tool, body|
    (body[:segments] || {}).flat_map do |entity, segs|
      segs.map { |name, seg| { tool:, entity:, name: name.to_s, seg: } }
    end
  end.freeze

  SLOT_SOURCE_ROWS = TOOLS.flat_map do |tool, body|
    %i[chat slash].flat_map do |branch|
      Array(body.dig(branch, :slots)).each_with_index.filter_map do |slot, i|
        { tool:, branch:, index: i, source: slot[:source] } if slot[:source]
      end
    end
  end.freeze

  REPLY_TARGET_ROWS = TOOLS.flat_map do |tool, body|
    Array(body.dig(:reply, :targets)&.keys).map { |target| { tool:, target: target.to_s } }
  end.freeze

  DESCRIPTION_KEYS = TOOLS.flat_map do |tool, body|
    keys = []
    keys << { where: "tools.#{tool}.description", key: body[:description] } if body[:description]
    %i[chat slash].each do |branch|
      desc = body.dig(branch, :description)
      keys << { where: "tools.#{tool}.#{branch}.description", key: desc } if desc
    end
    keys
  end.freeze

  DISPATCH_CLASS_ROWS = TOOLS.flat_map do |tool, body|
    %i[chat slash].filter_map do |branch|
      dispatch = body.dig(branch, :dispatch)
      { tool:, branch:, klass: dispatch } if dispatch.is_a?(String)
    end
  end.freeze

  before(:all) do
    Pito::FollowUp::Registry.register_all!
    Pito::Chat::Registry.register_all!
  end

  # ══ LAYER 1 — STRUCTURE ══════════════════════════════════════════════════════
  describe "STRUCTURE — the document is well-formed (Pito::Dispatch::Schema)" do
    it "the entire tools.yml passes structural validation with zero violations" do
      expect(STRUCTURAL_ERRORS).to(
        eq([]),
        -> { "structural violations:\n" + STRUCTURAL_ERRORS.map { |e| "  #{e}" }.join("\n") }
      )
    end

    # Per-tool granularity: a future author who breaks ONE tool sees only its errors.
    TOOLS.each_key do |tool|
      it "tools.#{tool} has no structural violations" do
        scoped = STRUCTURAL_ERRORS.select { |e| e.path == "tools.#{tool}" || e.path.start_with?("tools.#{tool}.") }
        expect(scoped).to(eq([]), -> { scoped.map { |e| "  #{e}" }.join("\n") })
      end
    end

    it "the universal_reply block passes structural validation" do
      scoped = STRUCTURAL_ERRORS.select { |e| e.path.start_with?("universal_reply") }
      expect(scoped).to(eq([]), -> { scoped.map { |e| "  #{e}" }.join("\n") })
    end

    it "no token maps to two tools within one dispatch namespace" do
      collisions = Pito::Dispatch::Schema.alias_collisions(DOC)
      expect(collisions).to(eq([]), -> { collisions.map { |e| "  #{e}" }.join("\n") })
    end

    it "every reply-target mode is a valid append/mutate enum" do
      bad = REPLY_TARGET_ROWS.reject do |row|
        mode = TOOLS.dig(row[:tool], :reply, :targets, row[:target].to_sym, :mode)
        Pito::Dispatch::Schema::REPLY_MODES.include?(mode)
      end
      expect(bad).to eq([])
    end
  end

  # ══ LAYER 2 — RESOLUTION ═════════════════════════════════════════════════════
  describe "RESOLUTION — every reference resolves against live code" do
    describe "segment builder constants exist (prefixed Pito::)" do
      SEGMENT_ROWS.each do |row|
        it "tools.#{row[:tool]}.segments.#{row[:entity]}.#{row[:name]}.builder → a builder" do
          const = "Pito::#{row[:seg][:builder]}"
          # Builders are module_function modules; jobs/handlers are classes — accept either.
          expect(const.safe_constantize).to(be_a(Module), "expected #{const} to name a class/module")
        end
      end
    end

    describe "segment fill jobs constantize when present (top-level)" do
      SEGMENT_ROWS.select { |r| r[:seg][:fill] }.each do |row|
        it "tools.#{row[:tool]}.segments.#{row[:entity]}.#{row[:name]}.fill → #{row[:seg][:fill]}" do
          expect(row[:seg][:fill].safe_constantize).to(be_a(Class), "expected #{row[:seg][:fill]} to name a job class")
        end
      end
    end

    describe "explicit dispatch server classes constantize (prefixed Pito::)" do
      DISPATCH_CLASS_ROWS.each do |row|
        it "tools.#{row[:tool]}.#{row[:branch]}.dispatch → Pito::#{row[:klass]}" do
          const = "Pito::#{row[:klass]}"
          expect(const.safe_constantize).to(be_a(Class), "expected #{const} to name a handler class")
        end
      end
    end

    describe "client-side dispatch kinds are on the allow-list" do
      it "themes uses a known client action" do
        client = TOOLS.dig(:themes, :slash, :dispatch, :client)
        expect(Pito::Dispatch::Schema::CLIENT_ACTIONS).to include(client)
      end
    end

    describe "description copy keys resolve through I18n" do
      DESCRIPTION_KEYS.each do |row|
        it "#{row[:where]} → #{row[:key]}" do
          expect(I18n.exists?(row[:key])).to(be(true), "missing i18n key #{row[:key]}")
        end
      end
    end

    describe "reply targets are registered FollowUp handlers" do
      REPLY_TARGET_ROWS.uniq { |r| r[:target] }.each do |row|
        it "reply target #{row[:target].inspect} is registered" do
          expect(Pito::FollowUp::Registry.for(row[:target])).to(be_present, "no FollowUp handler for #{row[:target]}")
        end
      end
    end

    describe "slot source vocabularies exist in Pito::Grammar::Vocabularies" do
      known = Pito::Grammar::Vocabularies.all.map(&:name).to_set

      SLOT_SOURCE_ROWS.each do |row|
        it "tools.#{row[:tool]}.#{row[:branch]}.slots[#{row[:index]}].source = #{row[:source]}" do
          expect(known).to include(row[:source].to_sym)
        end
      end
    end

    describe "resolver + predicate names are on their documented allow-lists" do
      it "every ref/args resolver name is a known resolver" do
        used = REPLY_TARGET_ROWS.flat_map do |row|
          target = TOOLS.dig(row[:tool], :reply, :targets, row[:target].to_sym)
          refs   = Array(target[:ref]&.values)
          args   = Array(target[:args]&.values).flat_map { |a| Array(a&.values) }
          refs + args
        end.compact.uniq
        expect(used - Pito::Dispatch::Schema::RESOLVERS).to eq([])
      end

      it "every segment emit_if predicate is a known predicate" do
        used = SEGMENT_ROWS.filter_map { |r| r[:seg][:emit_if] }.uniq
        expect(used - Pito::Dispatch::Schema::PREDICATES).to eq([])
      end
    end

    describe "Segments.for reads config coherently — each Segment mirrors its config entry" do
      # TABLE is gone; iterate only tools that declare a segments: block in tools.yml.
      TOOLS.select { |_, body| body[:segments] }.each_key do |tool|
        %i[channel vid game].each do |entity|
          next unless TOOLS.dig(tool, :segments, entity)

          it "#{tool}/#{entity}: names, order, kinds, defaults, builders, fills, targets, guards" do
            raw  = TOOLS.dig(tool, :segments, entity)
            segs = Pito::Chat::Segments.for(tool:, entity:)

            config_rows = raw.map do |name, seg|
              {
                name:         name.to_s,
                kind:         seg[:kind],
                default:      seg[:default],
                reply_target: seg[:reply_target],
                builder:      seg[:builder],
                fill:         seg[:fill],
                guarded:      !seg[:emit_if].nil?
              }
            end
            seg_rows = segs.map do |seg|
              {
                name:         seg.name,
                kind:         seg.kind.to_s,
                default:      seg.default,
                reply_target: seg.reply_target.to_s,
                builder:      seg.builder.name.delete_prefix("Pito::"),
                fill:         seg.fill&.name,
                guarded:      !seg.emit_if.nil?
              }
            end
            expect(seg_rows).to eq(config_rows)
          end
        end
      end
    end

    it "segment names and metric tokens are disjoint (unambiguous `with` clauses)" do
      segment_names = SEGMENT_ROWS.map { |r| r[:name] }.uniq
      metrics_vocab = Pito::Grammar::Registry.vocabulary(:metrics)
      metric_tokens = (
        Pito::Analytics::MetricSelection::ALIASES.keys +
        Pito::Analytics::MetricOrder::METRICS.keys.map(&:to_s) +
        metrics_vocab.canonical +
        metrics_vocab.synonyms.keys
      ).uniq
      expect(segment_names & metric_tokens).to eq([])
    end
  end

  # ══ LAYER 3 — OUTPUT ═════════════════════════════════════════════════════════
  describe "OUTPUT — Pito::Dispatch::Config read contracts are pinned" do
    it "tool(:show) is a frozen, symbol-keyed Hash carrying its branches" do
      show = Pito::Dispatch::Config.tool(:show)
      expect(show).to be_a(Hash)
      expect(show).to be_frozen
      expect(show.keys).to all(be_a(Symbol))
      expect(show).to include(:chat, :segments, :reply)
    end

    it "tool(:list) exposes its chat branch and pager concern, frozen deep" do
      list = Pito::Dispatch::Config.tool(:list)
      expect(list).to be_frozen
      expect(list[:chat]).to be_frozen
      expect(list.dig(:chat, :slots)).to be_an(Array).and be_frozen
      expect(list).to include(:concerns)
    end

    it "tool accepts a String name as well as a Symbol" do
      expect(Pito::Dispatch::Config.tool("show")).to equal(Pito::Dispatch::Config.tool(:show))
    end

    it "pager(tool: :list) is the exact list pager value" do
      expect(Pito::Dispatch::Config.pager(tool: :list)).to eq(page_size: 50, more_tool: "next")
    end

    it "pager(tool: :show) is nil (no pager concern declared)" do
      expect(Pito::Dispatch::Config.pager(tool: :show)).to be_nil
    end

    it "tool(:nope) raises a KeyError naming the unknown tool" do
      expect { Pito::Dispatch::Config.tool(:nope) }
        .to raise_error(KeyError, /unknown tool :nope/)
    end

    it "reload! clears memoization and re-reads an equal document" do
      before = Pito::Dispatch::Config.data
      expect(Pito::Dispatch::Config.reload!).to be_nil
      after = Pito::Dispatch::Config.data
      expect(after).to eq(before)
      expect(after).not_to equal(before)
    end

    it "every tool in tools.yml is resolvable through Config.tool" do
      expect(TOOLS.keys).to all(satisfy { |t| Pito::Dispatch::Config.tool(t).is_a?(Hash) })
    end
  end

  # ══ LAYER 4 — MCP (G130) ═════════════════════════════════════════════════════
  # The read-only MCP tool ontology lives in the SAME file. These guards enforce
  # what Pito::Dispatch::Schema can't check per-node (they need the whole DOC):
  # tool-name uniqueness, the read-only allowlist (a `mcp:` block on a WRITE tool
  # is a security regression → red), and grammar-template soundness. Structural
  # per-node validation (key/type/enum) is already covered by LAYER 1.
  describe "MCP — the read-only tool ontology is sound" do
    # Dispatch tools promoted to MCP tools, and the standalone reader tools.
    MCP_TOOL_ROWS   = TOOLS.filter_map { |tool, body| { tool: tool.to_s, block: body[:mcp] } if body[:mcp] }.freeze
    MCP_READER_ROWS = (DOC[:mcp_readers] || {}).map { |key, body| { key: key.to_s, block: body } }.freeze

    # The EXACT set of tools allowed to carry an `mcp:` block (the 11 documented
    # MCP reader tools). Adding a tool is a reviewed act: a new mcp block on a
    # tool NOT listed here is red until the author adds it — the guard against an
    # accidental exposure. (The add-a-tool proof exercises config extensibility
    # via injection, bypassing this shipped-config allowlist.)
    MCP_TOOL_ALLOWLIST = %w[
      list show analyze at-a-glance videos game similar channels breakdowns shinies games
    ].freeze

    # Tools that MUTATE state — they must NEVER be exposed as an MCP tool (owner
    # rule 1: read-only). An explicit blocklist makes the security intent legible.
    MCP_WRITE_TOOLS = %w[
      import publish unlist delete link unlink footage price platform schedule
      reindex sync find search rename connect disconnect login logout new resume
    ].freeze

    # All declared MCP tool names (dispatch-tool-backed + readers).
    MCP_TOOL_NAMES = (MCP_TOOL_ROWS.map { |r| r[:block][:tool] } +
                      MCP_READER_ROWS.map { |r| r[:block][:tool] }).freeze

    it "the tools carrying an mcp block are EXACTLY the read-only allowlist" do
      expect(MCP_TOOL_ROWS.map { |r| r[:tool] }).to match_array(MCP_TOOL_ALLOWLIST)
    end

    it "no write/mutating tool is exposed as an MCP tool" do
      exposed = MCP_TOOL_ROWS.map { |r| r[:tool] } & MCP_WRITE_TOOLS
      expect(exposed).to(eq([]), -> { "write tools exposed via mcp: #{exposed.inspect}" })
    end

    it "tool names are unique across dispatch-tool blocks and readers" do
      dupes = MCP_TOOL_NAMES.tally.select { |_, n| n > 1 }.keys
      expect(dupes).to(eq([]), -> { "duplicate tool names: #{dupes.inspect}" })
    end

    it "every declared tool surfaces in Pito::Mcp::Registry (config ⇒ registry loses nothing)" do
      expect(Pito::Mcp::Registry.tool_names).to match_array(MCP_TOOL_NAMES)
    end

    # ── per-dispatch-tool contracts ────────────────────────────────────────────
    MCP_TOOL_ROWS.each do |row|
      tool  = row[:tool]
      block = row[:block]

      describe "tools.#{tool}.mcp (#{block[:tool]})" do
        it "has a non-blank tool name and description" do
          expect(block[:tool].to_s).to match(/\S/)
          expect(block[:description].to_s).to match(/\S/)
        end

        it "declares an input grammar template" do
          expect(block[:input].to_s).to match(/\S/)
        end

        it "every %{placeholder} in `input` is a declared param" do
          placeholders = block[:input].to_s.scan(/%\{(\w+)\}/).flatten
          params       = (block[:params] || {}).keys.map(&:to_s)
          undeclared   = placeholders - params
          expect(undeclared).to(eq([]), -> { "input references undeclared params: #{undeclared.inspect}" })
        end

        it "every input_suffixes key is a declared param, templated with %{value}/%{values} only" do
          suffixes = block[:input_suffixes] || {}
          params   = (block[:params] || {}).keys.map(&:to_s)
          suffixes.each do |name, tmpl|
            expect(params).to include(name.to_s), "suffix #{name} is not a declared param"
            stray = tmpl.to_s.scan(/%\{(\w+)\}/).flatten - %w[value values]
            expect(stray).to(eq([]), -> { "suffix #{name} uses stray placeholders: #{stray.inspect}" })
          end
        end

        it "each param has a valid type and a boolean `required` when present" do
          (block[:params] || {}).each do |name, spec|
            expect(Pito::Dispatch::Schema::MCP_PARAM_TYPES).to include(spec[:type].to_s),
                                                                "param #{name} has an invalid type #{spec[:type].inspect}"
            expect([ true, false ]).to include(spec[:required]) if spec.key?(:required)
            expect(spec[:enum]).to(be_a(Array).and(be_present)) if spec.key?(:enum)
          end
        end
      end
    end

    # ── reader-tool contracts ──────────────────────────────────────────────────
    MCP_READER_ROWS.each do |row|
      block = row[:block]

      describe "mcp_readers.#{row[:key]} (#{block[:tool]})" do
        it "has a non-blank tool name and description" do
          expect(block[:tool].to_s).to match(/\S/)
          expect(block[:description].to_s).to match(/\S/)
        end

        it "declares NO input template or suffixes (readers are not dispatched)" do
          expect(block).not_to have_key(:input)
          expect(block).not_to have_key(:input_suffixes)
        end

        it "each param has a valid type" do
          (block[:params] || {}).each do |name, spec|
            expect(Pito::Dispatch::Schema::MCP_PARAM_TYPES).to include(spec[:type].to_s),
                                                                "param #{name} has an invalid type #{spec[:type].inspect}"
          end
        end
      end
    end
  end

  # ══ LAYER 5 — NL AUTO-RUN (3.0.1 P13) ════════════════════════════════════════
  # The NL gate (Pito::Chat::Handlers::Unknown) auto-runs a high-confidence
  # free-text match ONLY for read-only tools: the tool-level `read_only:`
  # declaration when present, else the `mcp.read_only` fallback. That predicate
  # decides what executes WITHOUT the owner confirming — so the exact effective
  # set is pinned here: a tools.yml edit that widens it is red until this
  # allowlist is deliberately, reviewably updated.
  describe "NL auto-run — the read-only auto-runnable set is pinned" do
    # Mirrors Pito::Chat::Handlers::Unknown#read_only? (tool-level key
    # authoritative when present — an explicit false wins — else mcp fallback).
    NL_AUTO_RUNNABLE = TOOLS.filter_map do |tool, body|
      effective = body.key?(:read_only) ? body[:read_only] == true : body.dig(:mcp, :read_only) == true
      tool.to_s if effective
    end.freeze

    # The EXACT set allowed to auto-run at high confidence (P13, locked): the
    # seven pure-read chat tools declaring tool-level `read_only: true`, plus
    # the seven tools already `mcp.read_only: true`.
    NL_AUTO_RUN_ALLOWLIST = %w[
      analyze at-a-glance breakdowns channels help linked search
      list show videos game similar shinies games
    ].freeze

    # Write-capable tools that must NEVER auto-run from NL (P13's explicit
    # list) — a belt to the exact-match suspenders, so the security intent is
    # legible even when the allowlist churns.
    NL_WRITE_TOOLS = %w[
      delete publish unlist schedule update link unlink import sync reindex
      footage price platform
    ].freeze

    it "the effective auto-runnable set is EXACTLY the pinned allowlist" do
      expect(NL_AUTO_RUNNABLE).to match_array(NL_AUTO_RUN_ALLOWLIST)
    end

    it "no write-capable tool is NL-auto-runnable" do
      runnable_writes = NL_AUTO_RUNNABLE & NL_WRITE_TOOLS
      expect(runnable_writes).to(eq([]), -> { "write tools auto-runnable from NL: #{runnable_writes.inspect}" })
    end

    it "every tool-level read_only declaration in the shipped file is `true` on a pinned tool" do
      declared = TOOLS.filter_map { |tool, body| tool.to_s if body[:read_only] == true }
      expect(declared - NL_AUTO_RUN_ALLOWLIST).to eq([])
    end
  end
end
