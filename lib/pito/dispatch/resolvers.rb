# frozen_string_literal: true

module Pito
  module Dispatch
    # Named resolver registry — the "escape hatch" from the tools.yml YAML schema.
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
        # @param name    [Symbol, String]  resolver name as declared in tools.yml
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
        handle = input.to_s.strip
        return Invalid.new(reason: "blank handle") if handle.empty?

        # Exact @-agnostic match, then a pg_trgm fuzzy fallback (#7) — shared with
        # the typed `show channel <handle>` path.
        ::Channel.resolve_handle(handle) || Invalid.new(reason: "channel not found: #{handle}")
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

      # :footage_hours
      # Parses the `footage [update] <hours>` amount typed on a game-detail reply
      # into an exact half-step Rational (ceil UP to the next 0.5 h). Wraps the
      # shared Pito::Games::FootageAmount parser — the SAME one the `footage` chat
      # tool and its GameDetail follow-up reply use (no fork). Non-numeric input
      # resolves Invalid.
      #
      # Required context: none. Input: the reply args after `footage`.
      register(:footage_hours, lambda { |input, context:|
        Pito::Games::FootageAmount.parse(input) ||
          Invalid.new(reason: "not a footage amount: #{input.inspect}")
      })

      # :price_amount
      # Parses the `price [set] <amount>` / `price unset` reply into either a
      # non-negative BigDecimal euro amount (2dp; 0 = free) or the `:unset`
      # sentinel. Wraps the shared Pito::Games::PriceAmount parser — the SAME one
      # the `price` chat tool and its GameDetail follow-up reply use (no fork).
      # An optional leading `set` is peeled; a leading `unset` short-circuits to
      # `:unset`. On a list target the leading row id is sliced off by ReplyBinding
      # before this runs (see LEADING_TOKEN_REFS), so the input is `<amount>` in
      # both the detail and list flows.
      #
      # Required context: none. Input: the reply args (after any sliced row id).
      register(:price_amount, lambda { |input, context:|
        tokens = input.to_s.strip.split(/\s+/)
        sub    = tokens.first&.downcase
        case sub
        when "unset"
          :unset
        when "set"
          Pito::Games::PriceAmount.parse(tokens[1]) ||
            Invalid.new(reason: "not a price amount: #{tokens[1].inspect}")
        else
          Pito::Games::PriceAmount.parse(tokens.first) ||
            Invalid.new(reason: "not a price amount: #{tokens.first.inspect}")
        end
      })

      # :platform_value
      # Normalises the `platform [set|unset] <value>` reply into a canonical stored
      # platform string (the logo family). Wraps Pito::Games::PlatformInput.normalize
      # — the SAME normaliser the `platform` chat tool uses (no fork) — after peeling
      # an optional leading set/unset subcommand and an optional `game(s)` noun filler.
      # The set-vs-unset OP stays handler-routed (this resolver yields the VALUE, the
      # bespoke parsing the TODO flagged). On a list target the leading row id is
      # sliced off by ReplyBinding first, so the input is `<value>` either way.
      #
      # Required context: none. Input: the reply args (after any sliced row id).
      register(:platform_value, lambda { |input, context:|
        text = input.to_s.strip
          .sub(/\A(?:set|unset)\b\s*/i, "") # peel optional subcommand
          .sub(/\A(?:game|games)\b\s*/i, "") # peel optional noun filler
        Pito::Games::PlatformInput.normalize(text).presence ||
          Invalid.new(reason: "no platform value in: #{input.inspect}")
      })

      # ── link / unlink dual-ref (source + target) ────────────────────────────────
      #
      # `link 5 to 12` / `unlink 5 from 12` (list) and `link to 12` / `unlink 12`
      # (detail, incl. game_linked_videos) carry a SOURCE and a TARGET. Both
      # resolvers derive the source/target model classes from the source event's
      # reply_target (video* → source Video, else source Game — exactly
      # Pito::Chat::TargetResolution#video_target?), and split the typed refs on the
      # connector words (`to`/`with`/`from`) internally, mirroring
      # Pito::Chat::Handlers::MultiLinkHelpers#follow_up_multi (wrap, don't fork).

      # Split a link/unlink reply into [left-of-connector, right-of-connector].
      LINK_CONNECTOR = /\b(?:to|with|from)\b/i
      # A leading game/vid noun filler to peel from a source or target slice.
      LINK_NOUN = /\A(?:game|games|vid|vids|video|videos)\b\s*/i

      # Source/target model classes for a link/unlink reply, from its reply_target.
      def self.link_roles(payload)
        source_class = payload[:reply_target].to_s.start_with?("video") ? ::Video : ::Game
        target_class = source_class == ::Video ? ::Game : ::Video
        [ source_class, target_class ]
      end

      # :link_source
      # Resolves the SOURCE record of a link/unlink reply. Detail context (the
      # source class's singular id is in the payload — incl. game_linked_videos,
      # whose parent game_id marks the Game as source): the entity from the payload.
      # List context: the id LEFT of the connector, scoped by the handler to a
      # numeric. Absent a typed numeric left id, a single-row list/search card
      # (the payload's video_ids/game_ids has exactly one id) implies the source —
      # mirroring Pito::Chat::Handlers::MultiLinkHelpers#follow_up_multi (wrap,
      # don't fork). Two-or-more rows (or zero) fall through to the existing
      # Invalid — explicit still beats implied.
      #
      # Required context: context[:source_event] (#payload → Hash with :reply_target
      # and the source id_key). Input: the full reply args.
      register(:link_source, lambda { |input, context:|
        source_event = context[:source_event]
        return Invalid.new(reason: "context[:source_event] required") unless source_event

        payload      = source_event.payload.to_h.with_indifferent_access
        source_class = link_roles(payload).first
        detail_key   = source_class == ::Video ? :video_id : :game_id

        if payload[detail_key].present?
          source_class.find_by(id: payload[detail_key]) ||
            Invalid.new(reason: "#{source_class} not found: #{payload[detail_key]}")
        else
          left = input.to_s.split(LINK_CONNECTOR, 2).first.to_s.strip.sub(LINK_NOUN, "")
          id   = left.delete_prefix("#").strip

          unless id.match?(/\A\d+\z/)
            # No typed numeric left — fall back to the card's displayed rows.
            id_list_key = source_class == ::Video ? :video_ids : :game_ids
            row_ids     = payload[id_list_key]
            id          = row_ids.first.to_s if row_ids.is_a?(Array) && row_ids.size == 1
          end

          next Invalid.new(reason: "no source id in: #{input.inspect}") unless id.match?(/\A\d+\z/)

          source_class.find_by(id:) || Invalid.new(reason: "#{source_class} not found: ##{id}")
        end
      })

      # :link_targets
      # Resolves the TARGET record(s) of a link/unlink reply — the comma/space id
      # list AFTER the connector (or, with no connector on a detail reply, the rest
      # minus a leading connector/noun). Returns an Array of records of the opposite
      # class; Invalid when no id parses or none of the ids resolve (mirroring the
      # handler's all-missing → not_found path).
      #
      # Required context: context[:source_event] (for the reply_target role split).
      # Input: the reply args (the source id, if any, stays on the connector's left).
      register(:link_targets, lambda { |input, context:|
        source_event = context[:source_event]
        return Invalid.new(reason: "context[:source_event] required") unless source_event

        payload      = source_event.payload.to_h.with_indifferent_access
        target_class = link_roles(payload).last

        parts        = input.to_s.split(LINK_CONNECTOR, 2)
        targets_text = parts.size >= 2 ? parts[1] : input.to_s.sub(/\A(?:to|with|from)\b\s*/i, "")
        targets_text = targets_text.to_s.strip.sub(LINK_NOUN, "")

        ids = targets_text.split(/[\s,]+/).map(&:strip)
                          .select { |t| t.match?(/\A#?\d+\z/) }
                          .map { |t| t.delete_prefix("#") }.uniq
        next Invalid.new(reason: "no target ids in: #{input.inspect}") if ids.empty?

        records = ids.filter_map { |id| target_class.find_by(id:) }
        records.presence || Invalid.new(reason: "no #{target_class} targets found in: #{input.inspect}")
      })
    end
  end
end
