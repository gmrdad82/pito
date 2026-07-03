# frozen_string_literal: true

require "rails_helper"

# ── The verbs.yml schema-integrity suite (plan-0.9.5 TS) ────────────────────────
#
# The owner's foundation: EVERY option in config/pito/verbs.yml is specced for
# accuracy, resolution, and output so future verbs/options can be added on solid
# ground. Three layers, each a failure-reporter for the future verb author:
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
RSpec.describe "verbs.yml schema integrity", type: :dispatch do
  # Load the real, frozen document once — the same structure the app dispatches on.
  Pito::Dispatch::Config.reload!
  DOC   = Pito::Dispatch::Config.data
  VERBS = DOC[:verbs]

  # Every structural violation in the real file, computed once (expected: none).
  STRUCTURAL_ERRORS = Pito::Dispatch::Schema.validate(DOC)

  # Flattened rows for table-driven resolution specs.
  SEGMENT_ROWS = VERBS.flat_map do |verb, body|
    (body[:segments] || {}).flat_map do |entity, segs|
      segs.map { |name, seg| { verb:, entity:, name: name.to_s, seg: } }
    end
  end.freeze

  SLOT_SOURCE_ROWS = VERBS.flat_map do |verb, body|
    %i[chat slash].flat_map do |branch|
      Array(body.dig(branch, :slots)).each_with_index.filter_map do |slot, i|
        { verb:, branch:, index: i, source: slot[:source] } if slot[:source]
      end
    end
  end.freeze

  REPLY_TARGET_ROWS = VERBS.flat_map do |verb, body|
    Array(body.dig(:reply, :targets)&.keys).map { |target| { verb:, target: target.to_s } }
  end.freeze

  DESCRIPTION_KEYS = VERBS.flat_map do |verb, body|
    keys = []
    keys << { where: "verbs.#{verb}.description", key: body[:description] } if body[:description]
    %i[chat slash].each do |branch|
      desc = body.dig(branch, :description)
      keys << { where: "verbs.#{verb}.#{branch}.description", key: desc } if desc
    end
    keys
  end.freeze

  DISPATCH_CLASS_ROWS = VERBS.flat_map do |verb, body|
    %i[chat slash].filter_map do |branch|
      dispatch = body.dig(branch, :dispatch)
      { verb:, branch:, klass: dispatch } if dispatch.is_a?(String)
    end
  end.freeze

  before(:all) do
    Pito::FollowUp::Registry.register_all!
    Pito::Chat::Registry.register_all!
  end

  # ══ LAYER 1 — STRUCTURE ══════════════════════════════════════════════════════
  describe "STRUCTURE — the document is well-formed (Pito::Dispatch::Schema)" do
    it "the entire verbs.yml passes structural validation with zero violations" do
      expect(STRUCTURAL_ERRORS).to(
        eq([]),
        -> { "structural violations:\n" + STRUCTURAL_ERRORS.map { |e| "  #{e}" }.join("\n") }
      )
    end

    # Per-verb granularity: a future author who breaks ONE verb sees only its errors.
    VERBS.each_key do |verb|
      it "verbs.#{verb} has no structural violations" do
        scoped = STRUCTURAL_ERRORS.select { |e| e.path == "verbs.#{verb}" || e.path.start_with?("verbs.#{verb}.") }
        expect(scoped).to(eq([]), -> { scoped.map { |e| "  #{e}" }.join("\n") })
      end
    end

    it "the universal_reply block passes structural validation" do
      scoped = STRUCTURAL_ERRORS.select { |e| e.path.start_with?("universal_reply") }
      expect(scoped).to(eq([]), -> { scoped.map { |e| "  #{e}" }.join("\n") })
    end

    it "no token maps to two verbs within one dispatch namespace" do
      collisions = Pito::Dispatch::Schema.alias_collisions(DOC)
      expect(collisions).to(eq([]), -> { collisions.map { |e| "  #{e}" }.join("\n") })
    end

    it "every reply-target mode is a valid append/mutate enum" do
      bad = REPLY_TARGET_ROWS.reject do |row|
        mode = VERBS.dig(row[:verb], :reply, :targets, row[:target].to_sym, :mode)
        Pito::Dispatch::Schema::REPLY_MODES.include?(mode)
      end
      expect(bad).to eq([])
    end
  end

  # ══ LAYER 2 — RESOLUTION ═════════════════════════════════════════════════════
  describe "RESOLUTION — every reference resolves against live code" do
    describe "segment builder constants exist (prefixed Pito::)" do
      SEGMENT_ROWS.each do |row|
        it "verbs.#{row[:verb]}.segments.#{row[:entity]}.#{row[:name]}.builder → a builder" do
          const = "Pito::#{row[:seg][:builder]}"
          # Builders are module_function modules; jobs/handlers are classes — accept either.
          expect(const.safe_constantize).to(be_a(Module), "expected #{const} to name a class/module")
        end
      end
    end

    describe "segment fill jobs constantize when present (top-level)" do
      SEGMENT_ROWS.select { |r| r[:seg][:fill] }.each do |row|
        it "verbs.#{row[:verb]}.segments.#{row[:entity]}.#{row[:name]}.fill → #{row[:seg][:fill]}" do
          expect(row[:seg][:fill].safe_constantize).to(be_a(Class), "expected #{row[:seg][:fill]} to name a job class")
        end
      end
    end

    describe "explicit dispatch server classes constantize (prefixed Pito::)" do
      DISPATCH_CLASS_ROWS.each do |row|
        it "verbs.#{row[:verb]}.#{row[:branch]}.dispatch → Pito::#{row[:klass]}" do
          const = "Pito::#{row[:klass]}"
          expect(const.safe_constantize).to(be_a(Class), "expected #{const} to name a handler class")
        end
      end
    end

    describe "client-side dispatch kinds are on the allow-list" do
      it "themes uses a known client action" do
        client = VERBS.dig(:themes, :slash, :dispatch, :client)
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
        it "verbs.#{row[:verb]}.#{row[:branch]}.slots[#{row[:index]}].source = #{row[:source]}" do
          expect(known).to include(row[:source].to_sym)
        end
      end
    end

    describe "resolver + predicate names are on their documented allow-lists" do
      it "every ref/args resolver name is a known resolver" do
        used = REPLY_TARGET_ROWS.flat_map do |row|
          target = VERBS.dig(row[:verb], :reply, :targets, row[:target].to_sym)
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
      # TABLE is gone; iterate only verbs that declare a segments: block in verbs.yml.
      VERBS.select { |_, body| body[:segments] }.each_key do |verb|
        %i[channel vid game].each do |entity|
          next unless VERBS.dig(verb, :segments, entity)

          it "#{verb}/#{entity}: names, order, kinds, defaults, builders, fills, targets, guards" do
            raw  = VERBS.dig(verb, :segments, entity)
            segs = Pito::Chat::Segments.for(verb:, entity:)

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
    it "verb(:show) is a frozen, symbol-keyed Hash carrying its branches" do
      show = Pito::Dispatch::Config.verb(:show)
      expect(show).to be_a(Hash)
      expect(show).to be_frozen
      expect(show.keys).to all(be_a(Symbol))
      expect(show).to include(:chat, :segments, :reply)
    end

    it "verb(:list) exposes its chat branch and pager concern, frozen deep" do
      list = Pito::Dispatch::Config.verb(:list)
      expect(list).to be_frozen
      expect(list[:chat]).to be_frozen
      expect(list.dig(:chat, :slots)).to be_an(Array).and be_frozen
      expect(list).to include(:concerns)
    end

    it "verb accepts a String name as well as a Symbol" do
      expect(Pito::Dispatch::Config.verb("show")).to equal(Pito::Dispatch::Config.verb(:show))
    end

    it "pager(verb: :list) is the exact list pager value" do
      expect(Pito::Dispatch::Config.pager(verb: :list)).to eq(page_size: 50, more_verb: "next")
    end

    it "pager(verb: :show) is nil (no pager concern declared)" do
      expect(Pito::Dispatch::Config.pager(verb: :show)).to be_nil
    end

    it "verb(:nope) raises a KeyError naming the unknown verb" do
      expect { Pito::Dispatch::Config.verb(:nope) }
        .to raise_error(KeyError, /unknown verb :nope/)
    end

    it "reload! clears memoization and re-reads an equal document" do
      before = Pito::Dispatch::Config.data
      expect(Pito::Dispatch::Config.reload!).to be_nil
      after = Pito::Dispatch::Config.data
      expect(after).to eq(before)
      expect(after).not_to equal(before)
    end

    it "every verb in verbs.yml is resolvable through Config.verb" do
      expect(VERBS.keys).to all(satisfy { |v| Pito::Dispatch::Config.verb(v).is_a?(Hash) })
    end
  end
end
