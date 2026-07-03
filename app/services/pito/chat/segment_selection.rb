# frozen_string_literal: true

module Pito
  module Chat
    # Parses the segment-selection clause shared by the +show+ / +analyze+ verbs.
    # The clause is always trailing — entity references (#id, @handle, ordinals)
    # come first; this module only touches tokens starting at the first introducer.
    #
    #   SegmentSelection.parse("show vid #123",                         verb: :show, entity: :vid)
    #   # => Selection(mode: :default, names: [...defaults...],     unknown: [], conflict: false)
    #
    #   SegmentSelection.parse("show vid #123 full",                    verb: :show, entity: :vid)
    #   # => Selection(mode: :full,    names: [...all...],          unknown: [], conflict: false)
    #
    #   SegmentSelection.parse("show vid #123 with at-a-glance",        verb: :show, entity: :vid)
    #   # => Selection(mode: :with,    names: [...defaults+req...], unknown: [], conflict: false)
    #
    #   SegmentSelection.parse("show game #123 only similar,channels",  verb: :show, entity: :game)
    #   # => Selection(mode: :only,    names: [...req...],          unknown: [], conflict: false)
    #
    #   SegmentSelection.parse("show game #123 without channels",              verb: :show, entity: :game)
    #   # => Selection(mode: :without, names: %w[detail similar linked-videos at-a-glance], unknown: [], conflict: false)
    #
    #   # analyze shares the raw string with MetricSelection — metric tokens live in
    #   # extra_vocabulary so they are silently skipped here (not reported as unknown):
    #   SegmentSelection.parse("analyze vid #1 with views,breakdowns",  verb: :analyze, entity: :vid,
    #                          extra_vocabulary: metric_tokens)
    #   # => Selection(mode: :with, names: %w[numbers breakdowns], unknown: [], conflict: false)
    #   #    ("views" belongs to MetricSelection — ignored here)
    #
    # Rules:
    #   * Introducers +with+, +only+, and standalone +full+ are case-insensitive.
    #   * Token lists split on commas and/or whitespace; dash-case names only.
    #   * Each token is validated against Pito::Chat::Segments.names(verb:, entity:);
    #     tokens in +extra_vocabulary+ (downcased exact match) are silently skipped —
    #     they belong to another parser (e.g. MetricSelection) and are never reported
    #     as +unknown+.
    #   * All other unrecognised tokens land in +unknown+ and are never guessed.
    #   * +conflict+ is true when more than one of full / with / only / without appears;
    #     the parse is still returned (caller renders the error copy via Pito::Copy).
    #   * No user-facing strings are produced here — that is the caller's job.
    module SegmentSelection
      # Immutable value object returned by .parse.
      #
      # @!attribute mode     [Symbol]         :default | :full | :with | :only | :without
      # @!attribute names    [Array<String>]  validated segment names in table order
      # @!attribute unknown  [Array<String>]  raw tokens that did not validate
      # @!attribute conflict [Boolean]        true when multiple introducer keywords clash
      Selection = Data.define(:mode, :names, :unknown, :conflict)

      module_function

      # Matches the standalone word +full+ (not embedded inside another word).
      FULL_RE = /\bfull\b/i

      # Captures the token list after +with+; list ends at +only+, +full+, +without+, or EOI.
      WITH_RE = /\bwith\s+(.+?)(?=\s+\b(?:only|full|without)\b|\z)/i

      # Captures the token list after +only+; list ends at +with+, +full+, +without+, or EOI.
      ONLY_RE = /\bonly\s+(.+?)(?=\s+\b(?:with|full|without)\b|\z)/i

      # Captures the token list after +without+; list ends at +with+, +only+, +full+, +without+, or EOI.
      WITHOUT_RE = /\bwithout\s+(.+?)(?=\s+\b(?:with|only|full|without)\b|\z)/i

      # @param raw              [String]        raw command text as the user typed it.
      # @param verb             [Symbol]        the verb being dispatched (:show, :analyze, …).
      # @param entity           [Symbol]        the entity KIND (:channel/:vid/:game) — the Segments
      #   table key, NOT a record.
      # @param extra_vocabulary [Array<String>] tokens that belong to another parser (e.g.
      #   MetricSelection's metric names + aliases). Matched tokens (downcased, exact) are
      #   silently ignored — neither validated as segments nor reported as +unknown+.
      # @return [Selection]
      def parse(raw, verb:, entity:, extra_vocabulary: [])
        text = raw.to_s

        has_full      = FULL_RE.match?(text)
        with_match    = WITH_RE.match(text)
        only_match    = ONLY_RE.match(text)
        without_match = WITHOUT_RE.match(text)

        has_with    = !with_match.nil?
        has_only    = !only_match.nil?
        has_without = !without_match.nil?

        conflict = [ has_full, has_with, has_only, has_without ].count(true) > 1

        all_names       = Segments.names(verb: verb, entity: entity)
        default_names   = Segments.default_names(verb: verb, entity: entity)
        extra_vocab_set = extra_vocabulary.map { |t| t.to_s.downcase }.to_set
        alias_map       = Segments.alias_map(verb: verb, entity: entity)

        if has_only
          requested, unknown = validate_tokens(only_match[1], all_names, extra_vocab_set, alias_map)
          mode  = :only
          names = reorder(requested, all_names)
        elsif has_with
          requested, unknown = validate_tokens(with_match[1], all_names, extra_vocab_set, alias_map)
          mode  = :with
          names = reorder(default_names | requested, all_names)
        elsif has_without
          requested, unknown = validate_tokens(without_match[1], all_names, extra_vocab_set, alias_map)
          mode  = :without
          names = all_names - requested
        elsif has_full
          unknown = []
          mode    = :full
          names   = all_names
        else
          unknown = []
          mode    = :default
          names   = default_names
        end

        Selection.new(mode: mode, names: names, unknown: unknown, conflict: conflict)
      end

      # Builds the Selection that an `only <segment>` clause parses to for this
      # verb+entity — the seam segment verbs (plan-0.9.5 D20) use to force a single
      # segment WITHOUT rewriting the input string. A segment name absent from the
      # entity's table lands in +unknown+ (exactly as a typo in a real `only`
      # clause would), so the caller renders the identical `segments.unknown`
      # rejection. The output is byte-identical to
      # `parse("… only <segment>", verb:, entity:)`.
      #
      # @param verb    [Symbol]
      # @param entity  [Symbol]  :channel / :vid / :game
      # @param segment [String]  the dash-case canonical segment name to force
      # @return [Selection]
      def only(verb:, entity:, segment:)
        all = Segments.names(verb: verb, entity: entity)
        if all.include?(segment)
          Selection.new(mode: :only, names: [ segment ], unknown: [], conflict: false)
        else
          Selection.new(mode: :only, names: [], unknown: [ segment ], conflict: false)
        end
      end

      # Returns +raw+ with the selection clause(s) removed — the text entity
      # REFERENCE extraction should see (`"show game 5 full"` → `"show game 5"`).
      # Uses the same regexes as .parse so the two views of one input can never
      # drift. Unknown/metric tokens inside a with/only list are removed too —
      # they belong to the clause, not the reference.
      #
      # @param raw [String]
      # @return [String]
      def strip(raw)
        raw.to_s.gsub(WITH_RE, "").gsub(ONLY_RE, "").gsub(WITHOUT_RE, "").gsub(FULL_RE, "").squeeze(" ").strip
      end

      # Splits a comma- and/or whitespace-separated token string and partitions
      # each downcased token into validated vs unknown buckets.
      #
      # Tokens present in +extra_vocab_set+ are silently skipped — they belong to
      # another parser (e.g. MetricSelection) and must not pollute +unknown+.
      #
      # @param list_str       [String]        captured text from a regex group.
      # @param all_names      [Array<String>] all valid segment names for this verb+entity.
      # @param extra_vocab_set [Set<String>]  downcased tokens that belong to another parser.
      # @param alias_map      [Hash<String,String>] alias/canonical → canonical name map
      #   (built from Segments.alias_map); canonical names are identity-mapped so
      #   both aliases and canonical tokens resolve through a single look-up.
      # @return [Array(Array<String>, Array<String>)] [validated, unknown]
      def validate_tokens(list_str, all_names, extra_vocab_set = Set.new, alias_map = {})
        valid_set = all_names.to_set
        validated = []
        unknown   = []

        list_str.strip.split(/[\s,]+/).each do |tok|
          norm     = tok.strip.downcase
          next if norm.empty?

          # Resolve alias → canonical (identity map covers canonical names directly).
          resolved = alias_map.fetch(norm, norm)

          if valid_set.include?(resolved)
            validated << resolved   # always store the CANONICAL name, never the alias
          elsif extra_vocab_set.include?(norm)
            next  # belongs to another parser — not a segment, not unknown
          else
            unknown << norm
          end
        end

        [ validated.uniq, unknown ]
      end

      # Returns elements of +all_names+ that appear in +chosen+, preserving
      # the canonical table order and deduplicating.
      #
      # @param chosen    [Array<String>]
      # @param all_names [Array<String>]
      # @return [Array<String>]
      def reorder(chosen, all_names)
        chosen_set = chosen.to_set
        all_names.select { |n| chosen_set.include?(n) }
      end
    end
  end
end
