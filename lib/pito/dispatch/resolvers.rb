# frozen_string_literal: true

module Pito
  module Dispatch
    # Named resolver registry — the §5 "escape hatch" from the verbs.yml YAML schema.
    #
    # A resolver is a thin adapter that wraps EXISTING parsing/lookup code behind the
    # uniform contract:
    #
    #   call(input, context:) → value | Resolvers::Invalid.new(reason: "…")
    #
    # `input`   — the raw string extracted from the command or reply (what to resolve).
    # `context` — a plain keyword Hash carrying domain objects the adapter needs.
    #             Each adapter documents its required context keys in its comment.
    #
    # The adapters live here (small lambdas delegating to the existing parsers). The
    # parsers and finders themselves stay where they are and keep their own specs.
    #
    # Registry API
    # ============
    #   Resolvers.register(:name, callable)         — add an adapter (called at file-load)
    #   Resolvers.resolve(:name, input, context: {}) — run one; raises KeyError if unknown
    #   Resolvers.registered?(:name)                — predicate
    #   Resolvers.names                             — sorted, frozen Array<Symbol> of all names
    #
    # See docs/claude/0.9.5-yaml-schema.md §5 for the design contract.
    module Resolvers
      # Returned when a resolver cannot produce a valid value.
      # Callers pattern-match on the return type (value vs. Invalid).
      Invalid = Data.define(:reason)

      # ── Registry mechanics ──────────────────────────────────────────────────────

      @_registry = {}

      class << self
        # Register an adapter under +name+. The callable must respond to
        # #call(input, context:) → value | Invalid.
        #
        # Called at module-body level during file load — not at runtime.
        def register(name, callable)
          @_registry[name.to_sym] = callable
        end

        # Invoke the resolver registered as +name+ with +input+ and +context+.
        #
        # @param name    [Symbol, String]  resolver name as declared in verbs.yml
        # @param input   [String]          raw token/phrase to resolve
        # @param context [Hash]            domain objects the adapter needs (see adapters)
        # @return        the value produced by the adapter, or an Invalid instance
        # @raise         [KeyError] when +name+ is not registered
        def resolve(name, input, context: {})
          callable = @_registry.fetch(name.to_sym) { raise KeyError, "unknown resolver: #{name.inspect}" }
          callable.call(input, context:)
        end

        # Returns true when +name+ has an adapter registered.
        def registered?(name)
          @_registry.key?(name.to_sym)
        end

        # Alphabetically-sorted, frozen Array<Symbol> of all registered resolver names.
        # Registrations happen only at file-load time, so the cost is negligible.
        def names
          @_registry.keys.sort.freeze
        end
      end

      # ── Adapters ──────────────────────────────────────────────────────────────
      #
      # Each adapter delegates to an existing parser or ActiveRecord finder.
      # The underlying implementations stay where they are and keep their own specs.
      #
      # Registration order is irrelevant; +names+ always returns alphabetical order.
      # ─────────────────────────────────────────────────────────────────────────────

      # :channel_by_handle
      # Resolves a "@handle" or bare "handle" string to a ::Channel record.
      #
      # Required context: none.
      register(:channel_by_handle, lambda { |input, context:|
        handle = input.to_s.sub(/\A@/, "").strip
        return Invalid.new(reason: "blank handle") if handle.empty?

        ::Channel.find_by(handle:) || Invalid.new(reason: "channel not found: #{handle}")
      })

      # :video_by_id
      # Resolves a "#N" or plain "N" string to a ::Video record.
      #
      # Required context: none.
      register(:video_by_id, lambda { |input, context:|
        id = input.to_s.sub(/\A#\s*/, "").strip
        return Invalid.new(reason: "not a numeric id: #{input.inspect}") unless id.match?(/\A\d+\z/)

        ::Video.find_by(id:) || Invalid.new(reason: "video not found: ##{id}")
      })

      # :game_by_id
      # Resolves a "#N" or plain "N" string to a ::Game record.
      #
      # Required context: none.
      register(:game_by_id, lambda { |input, context:|
        id = input.to_s.sub(/\A#\s*/, "").strip
        return Invalid.new(reason: "not a numeric id: #{input.inspect}") unless id.match?(/\A\d+\z/)

        ::Game.find_by(id:) || Invalid.new(reason: "game not found: ##{id}")
      })

      # :id_among_rows
      # Resolves a "#N" or "N" ref to an entity record, constrained to be among
      # the source event's list rows. Falls back to a case-insensitive title ILIKE
      # lookup for non-numeric refs. When +source_event+ is absent the list-scope
      # constraint is skipped (any matching record is returned).
      #
      # Required context:
      #   context[:entity_class]  — the AR model class to look up (::Game, ::Video, …)
      #   context[:source_event]  — the source follow-up event; must respond to
      #                             #payload returning a Hash with :table_rows entries
      #                             shaped as { cells: [{ text: "#N" }, …] } or the
      #                             legacy { key: "#N", value: … } form.
      #                             Pass nil to skip the list-scope check.
      register(:id_among_rows, lambda { |input, context:|
        entity_class = context[:entity_class]
        return Invalid.new(reason: "context[:entity_class] required") unless entity_class

        ref = input.to_s.strip
        return Invalid.new(reason: "blank ref") if ref.blank?

        id_str = ref.sub(/\A#\s*/, "")
        record = if id_str.match?(/\A\d+\z/)
          entity_class.find_by(id: id_str)
        else
          entity_class.find_by("title ILIKE ?", ref)
        end
        return Invalid.new(reason: "record not found: #{ref.inspect}") if record.nil?

        source_event = context[:source_event]
        if source_event
          payload  = source_event.payload.to_h.with_indifferent_access
          row_ids  = Array(payload[:table_rows]).filter_map do |row|
            text = row[:cells] ? Array(row[:cells]).first&.dig(:text) : row[:key]
            next if text.blank?

            digits = text.to_s.sub(/\A#\s*/, "")
            digits.to_i if digits.match?(/\A\d+\z/)
          end
          unless row_ids.empty? || row_ids.include?(record.id)
            return Invalid.new(reason: "#{record.class}##{record.id} is not in the source list")
          end
        end

        record
      })

      # :schedule_expression
      # Parses a schedule <when> phrase ("in 30m", "tomorrow at 3pm", "DD-MM-YYYY")
      # to an ActiveSupport::TimeWithZone value interpreted in Time.zone.
      # Delegates to Pito::Schedule::TimeParser.
      #
      # TimeParser expects at least one leading "ref" token before the <when> phrase.
      # A synthetic numeric ref token is prepended so split-point 1 covers the full
      # input as the <when> phrase without changing the parser's behaviour.
      #
      # Required context: none.
      # Optional context:
      #   context[:now]  — Time value substituted for Time.current (useful in specs)
      register(:schedule_expression, lambda { |input, context:|
        raw_tokens    = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input.to_s))
        # Prepend a synthetic "0" ref token so TimeParser's split-at-1 iteration
        # tries the full input as the <when> phrase. Mirrors the pattern used by
        # Chat::Handlers::Schedule#prepend_follow_up_ref.
        synthetic_ref = Pito::Lex::Token.new(type: :number, value: "0", position: -1,
                                              preceded_by_space: false)
        tokens = [ synthetic_ref ] + raw_tokens
        now    = context[:now] || Time.current
        result = Pito::Schedule::TimeParser.call(tokens, now:)
        result&.time || Invalid.new(reason: "unrecognized schedule expression: #{input.inspect}")
      })

      # :column_list
      # Parses the `with <col>[, <col>…]` clause from a raw command string.
      # Delegates to Pito::Chat::WithColumns.parse.
      #
      # Required context:
      #   context[:vocabulary]  — Hash{String => Object} of token → canonical value.
      #                           Obtain per entity via e.g.
      #                           Pito::MessageBuilder::Game::ListColumns.vocabulary
      register(:column_list, lambda { |input, context:|
        vocab  = context[:vocabulary] || {}
        result = Pito::Chat::WithColumns.parse(input.to_s, vocabulary: vocab)
        result.empty? ? Invalid.new(reason: "no recognized columns in: #{input.inspect}") : result
      })

      # :sort_clause
      # Parses the sort/order [by] <col> [asc|desc] clause from a raw command string.
      # Delegates to Pito::Chat::SortClause.parse.
      #
      # Required context: none.
      register(:sort_clause, lambda { |input, context:|
        result = Pito::Chat::SortClause.parse(input.to_s)
        result || Invalid.new(reason: "no sort clause in: #{input.inspect}")
      })

      # :metric_list
      # Parses the `with`/`without` metric clauses from a raw command string.
      # Returns a Pito::Analytics::MetricSelection::Selection when at least one
      # metric is specified; Invalid otherwise.
      # Delegates to Pito::Analytics::MetricSelection.parse.
      #
      # Required context: none.
      register(:metric_list, lambda { |input, context:|
        result = Pito::Analytics::MetricSelection.parse(input.to_s)
        result.any? ? result : Invalid.new(reason: "no metrics specified in: #{input.inspect}")
      })

      # :game_titles
      # Resolves a title-prefix string to a list of matching ::Game titles for
      # autocomplete. Delegates to the :game_titles dynamic vocabulary registered
      # in Pito::Grammar::Registry (backed by ConfigSource, ILIKE prefix query, limit 20).
      #
      # Required context: none.
      # Input: the title prefix string used as the ILIKE pattern context.
      register(:game_titles, lambda { |input, context:|
        titles = Pito::Grammar::Registry.vocabulary(:game_titles).members(context: input.to_s)
        titles.present? ? titles : Invalid.new(reason: "no game titles matched #{input.inspect}")
      })

      # :visit_destination
      # Resolves a raw destination token to a canonical destination string.
      # Accepts: "channel", "studio", and their synonyms ("youtube", "yt").
      # Delegates to the :visit_destinations vocabulary registered in
      # Pito::Grammar::Registry (backed by ConfigSource).
      #
      # Required context: none.
      register(:visit_destination, lambda { |input, context:|
        raw   = input.to_s.strip.downcase
        vocab = Pito::Grammar::Registry.vocabulary(:visit_destinations)
        canonical = vocab.canonical.find { |c| c.downcase == raw } || vocab.synonyms[raw]
        canonical || Invalid.new(reason: "unknown visit destination: #{raw.inspect}")
      })

      # :source_entity
      # Resolves the entity a follow-up SOURCE EVENT is *about* — the detail
      # card's (or import card's) own record — from its payload <id_key> field.
      # This is the "detail context" resolution mode named: today it lives inline
      # in Pito::Chat::TargetResolution#resolve_target (the `payload[id_key]`
      # branch) and in each detail handler's `resolve_*_from_event`. A reply
      # branch declares `ref: { resolver: source_entity }` to say "the ref comes
      # from the source event, not from typed reply text".
      #
      # The +input+ argument is IGNORED — the id lives in the event, not the
      # reply. The declaration carries no typed ref (e.g. `#<handle> reindex`).
      #
      # Required context:
      #   context[:entity_class] — the AR model class (::Game, ::Video, ::Channel).
      #   context[:id_key]       — the payload field holding the id (e.g. :game_id).
      #   context[:source_event] — the source follow-up event; #payload → Hash.
      register(:source_entity, lambda { |_input, context:|
        entity_class = context[:entity_class]
        id_key       = context[:id_key]
        source_event = context[:source_event]
        return Invalid.new(reason: "context[:entity_class] required") unless entity_class
        return Invalid.new(reason: "context[:id_key] required")       unless id_key
        return Invalid.new(reason: "context[:source_event] required") unless source_event

        payload = source_event.payload.to_h.with_indifferent_access
        id      = payload[id_key]
        return Invalid.new(reason: "source event has no #{id_key}") if id.blank?

        entity_class.find_by(id:) || Invalid.new(reason: "#{entity_class} not found: #{id}")
      })
    end
  end
end
