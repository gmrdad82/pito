# frozen_string_literal: true

module Pito
  module Dispatch
    # ReplyBinding — the declarative consumption seam for a reply branch's
    # `reply.targets.<target>.ref` / `.args` resolver paths (plan-0.9.5 T8.7).
    #
    # Given a follow-up reply — `#<handle> <verb> <rest>` on a source event whose
    # `reply_target` is <target> — this reads the verb's declared ref/args paths
    # from config/pito/verbs.yml (via Pito::Dispatch::Config) and runs each named
    # resolver through Pito::Dispatch::Resolvers, producing a Hash of resolved
    # kwargs:
    #
    #   ReplyBinding.bind(verb: "show", target: "game_list", rest: "5",
    #                     source_event: ev, conversation: c)
    #   # => Result(kwargs: { ref: #<Game id: 5> }, invalid: nil)
    #
    # It is the SINGLE place that reads those declared paths; VerbDelegator
    # consults it and threads the result onto Pito::Chat::FollowUpContext#bound.
    # In P2 the handlers still do their own extraction — the bound kwargs are
    # advisory (nothing downstream reads them yet), which is exactly why the
    # frozen dispatch matrices stay green. The P3 Router (T8.10) is what flips
    # consumption so the binding becomes authoritative-in-effect.
    #
    # == Input contract (how each resolver reads the reply)
    #
    # The reply's text is split into the +verb+ word and +rest+ (everything
    # after it — the same value FollowUpContext#rest carries). Each resolver was
    # written (T8.6) against a specific raw-input shape; the binding feeds it the
    # matching slice per INPUT_MODE:
    #
    #   :args      → +rest+ verbatim (a bare ref / handle / id / word / when-phrase)
    #   :full_rest → "<verb> <rest>" (clause scanners that locate their own magic
    #                keyword — `with …`, `sort …` — in the whole command)
    #   :source    → +rest+ is ignored; the resolver reads the source event payload
    #
    # == Resolver context
    #
    # The entity class + payload id-key a resolver needs are derived from the
    # target (TARGET_META) — a list target scopes to its rows, a detail/import
    # target reads its card's id. The per-entity column vocabulary (for
    # `column_list`) is derived from the same entity class.
    #
    # == Return
    #
    # Result#kwargs is the resolved Hash ({ ref: …, <arg_name>: … }); Result#ok?
    # is true when nothing failed. The FIRST resolver that yields a
    # Resolvers::Invalid short-circuits: Result#invalid carries it (a
    # BoundInvalid naming the failed slot) and kwargs is empty. Targets that
    # declare no ref/args — and verbs/targets absent from the config — yield an
    # empty, ok Result (nothing to bind).
    module ReplyBinding
      # A successful binding's kwargs + the first Invalid, if any.
      Result = Data.define(:kwargs, :invalid) do
        # True when every declared path resolved.
        def ok? = invalid.nil?
      end

      # Wraps a resolver's Invalid with the slot (:ref or an arg name) it failed on.
      BoundInvalid = Data.define(:slot, :resolver, :reason)

      # How the binding feeds each resolver its input (see the class comment).
      # Unlisted resolvers default to :args (a bare token is the safe default).
      INPUT_MODE = {
        "id_among_rows"       => :args,
        "channel_by_handle"   => :args,
        "video_by_id"         => :args,
        "game_by_id"          => :args,
        "visit_destination"   => :args,
        "schedule_expression" => :args,
        "source_entity"       => :source,
        "column_list"         => :full_rest,
        "sort_clause"         => :full_rest,
        "metric_list"         => :full_rest
      }.freeze

      # Per reply_target: the AR model class name + the payload id-key that
      # identifies the entity the source card is about (for id_among_rows scope
      # and source_entity lookup). A frozen projection of the follow-up handlers'
      # ground truth (game_id / video_id / channel_id payload stamping).
      TARGET_META = {
        "channel_detail"     => { entity: "::Channel", id_key: :channel_id },
        "channel_visit"      => { entity: "::Channel", id_key: :channel_id },
        "channel_list"       => { entity: "::Channel", id_key: :channel_id },
        "game_detail"        => { entity: "::Game",    id_key: :game_id },
        "game_imported"      => { entity: "::Game",    id_key: :game_id },
        "game_similar"       => { entity: "::Game",    id_key: :game_id },
        "game_list"          => { entity: "::Game",    id_key: :game_id },
        "game_channels"      => { entity: "::Channel", id_key: :channel_id },
        "game_linked_videos" => { entity: "::Video",   id_key: :video_id },
        "video_detail"       => { entity: "::Video",   id_key: :video_id },
        "video_list"         => { entity: "::Video",   id_key: :video_id }
      }.freeze

      # Per-entity column vocabulary provider (only column_list uses it).
      COLUMN_VOCABULARY = {
        "::Game"  => -> { Pito::MessageBuilder::Game::ListColumns.vocabulary },
        "::Video" => -> { Pito::MessageBuilder::Video::ListColumns.vocabulary }
      }.freeze

      module_function

      # Resolve a reply's declared ref/args into kwargs.
      #
      # @param verb          [String, Symbol] the reply verb token typed (alias ok).
      # @param target        [String, Symbol] the source event's reply_target.
      # @param rest          [String]         reply text AFTER the verb word.
      # @param source_event  [#payload]       the live event being replied to.
      # @param conversation  [Conversation, nil] threaded for future resolvers.
      # @return [Result]
      def bind(verb:, target:, rest:, source_event:, conversation: nil)
        target_cfg = target_config(verb, target)
        return Result.new(kwargs: {}, invalid: nil) if target_cfg.nil?

        kwargs = {}

        if (ref_cfg = target_cfg[:ref])
          outcome = resolve_slot(ref_cfg[:resolver], :ref,
                                 verb:, target:, rest:, source_event:, conversation:)
          return invalid_result(outcome) if outcome.is_a?(BoundInvalid)

          kwargs[:ref] = outcome
        end

        (target_cfg[:args] || {}).each do |name, spec|
          outcome = resolve_slot(spec[:resolver], name,
                                 verb:, target:, rest:, source_event:, conversation:)
          return invalid_result(outcome) if outcome.is_a?(BoundInvalid)

          kwargs[name.to_sym] = outcome
        end

        Result.new(kwargs:, invalid: nil)
      end

      # ── internals ──────────────────────────────────────────────────────────

      # The frozen `reply.targets.<target>` Hash for the verb (canonicalizing an
      # alias to its verb first), or nil when the verb / target / reply branch is
      # absent from the config.
      def target_config(verb, target)
        canonical = Pito::Dispatch::Matrix.verb_for(verb.to_s.downcase) || verb.to_s
        verb_cfg  =
          begin
            Pito::Dispatch::Config.verb(canonical)
          rescue KeyError
            return nil
          end
        verb_cfg.dig(:reply, :targets, target.to_s.to_sym)
      end

      # Run one resolver for the +slot+ (:ref or an arg name). Returns the
      # resolved value, or a BoundInvalid when the resolver yields Invalid.
      def resolve_slot(resolver, slot, verb:, target:, rest:, source_event:, conversation:)
        input   = resolver_input(resolver, verb:, rest:)
        context = resolver_context(target:, source_event:, conversation:)
        value   = Pito::Dispatch::Resolvers.resolve(resolver, input, context:)
        return value unless value.is_a?(Pito::Dispatch::Resolvers::Invalid)

        BoundInvalid.new(slot:, resolver: resolver.to_s, reason: value.reason)
      end

      def resolver_input(resolver, verb:, rest:)
        case INPUT_MODE.fetch(resolver.to_s, :args)
        when :full_rest then "#{verb} #{rest}".strip
        else                 rest.to_s # :args and :source (source ignores it)
        end
      end

      def resolver_context(target:, source_event:, conversation:)
        meta         = TARGET_META[target.to_s] || {}
        entity_class = constantize(meta[:entity])
        {
          entity_class:,
          id_key:       meta[:id_key],
          source_event:,
          conversation:,
          vocabulary:   vocabulary_for(meta[:entity])
        }
      end

      def vocabulary_for(entity_name)
        provider = COLUMN_VOCABULARY[entity_name]
        provider ? provider.call : {}
      end

      def constantize(name)
        name&.constantize
      rescue NameError
        nil
      end

      def invalid_result(bound_invalid)
        Result.new(kwargs: {}, invalid: bound_invalid)
      end
    end
  end
end
