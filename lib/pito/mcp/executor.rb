# frozen_string_literal: true

module Pito
  module Mcp
    # Runs one MCP tool call. For a chat-tool-backed tool it builds a chat GRAMMAR string
    # from the tool's `input` template + `input_suffixes` (the same grammar a human
    # types), routes it through the UNMODIFIED Pito::Dispatch::Router, and projects
    # the Result's events to markdown via EventText — so the server's grammar stays
    # the single behaviour authority and MCP adds no parallel logic.
    #
    # READ-ONLY, NON-PERSISTING by construction: Router.call returns handler Results
    # and writes nothing; persistence lives in the dispatch JOBS, which MCP never
    # invokes. This class must never create/update/enqueue (the one allowed write —
    # the anchor Conversation — is minted by #mcp_conversation). The spec
    # proves Event.count is unchanged across a call.
    #
    # Pending analytics (analyze / breakdowns / glance / channels) normally fill via
    # jobs + Turbo; MCP is pull-only, so the Executor computes them INLINE, wired
    # into #fill_pending. Errors (Result::Error) render through EventText
    # like any error event.
    module Executor
      module_function

      # Params forwarded to Router.call as keywords instead of interpolated into the
      # grammar string (they are not chat text). `period` is the only one today.
      ROUTER_FORWARDABLE = %i[period].freeze

      Result = Struct.new(:text, :is_error, keyword_init: true) do
        def error? = is_error
      end

      class UnknownTool < StandardError; end

      # @param tool [String] the MCP tool name (e.g. "pito_show")
      # @param arguments [Hash] the tool-call arguments (string- or symbol-keyed)
      # @return [Result] text (markdown) + is_error
      def call(tool:, arguments: {})
        descriptor = Registry.tool(tool)
        raise UnknownTool, tool.to_s if descriptor.nil?

        args = stringify(arguments)
        case descriptor[:kind]
        when :verb   then execute_verb(descriptor, args)
        when :reader then execute_reader(descriptor, args)
        end
      end

      # ── chat-tool-backed tools ──────────────────────────────────────────────────

      def execute_verb(descriptor, args)
        missing = missing_required(descriptor, args)
        return Result.new(text: missing_message(missing), is_error: true) if missing.any?

        invalid = validation_errors(descriptor, args)
        return Result.new(text: invalid.join("\n"), is_error: true) if invalid.any?

        result = Pito::Dispatch::Router.call(
          input:        build_input(descriptor, args),
          conversation: mcp_conversation,
          **router_kwargs(descriptor, args)
        )
        events = fill_pending(Pito::Dispatch::Finalizer.result_events(result))
        Result.new(text: EventText.call(events), is_error: error?(result))
      end

      # Reader tools (pito_conversations / pito_messages) — persisted-row readers
      # that dispatch nothing through the Router (source: "app" SELECTs → EventText).
      def execute_reader(descriptor, args)
        Readers.call(descriptor[:name], args)
      end

      # Inline-fill pending analytics markers so the MCP caller never receives a
      # "pending" placeholder — the compute happens synchronously in AnalyticsFill.
      def fill_pending(events)
        AnalyticsFill.call(events)
      end

      # ── grammar string construction ────────────────────────────────────────────

      # `input` carries the required params inline ("show %{noun} %{ref}");
      # `input_suffixes` append an optional param's clause when it is present
      # (" with %{values}"). Arrays join with ", " — the universal separator the
      # chat grammar accepts for columns / ids / segments (space breaks columns).
      def build_input(descriptor, args)
        input    = interpolate(descriptor[:input].to_s, args)
        appended = false
        (descriptor[:input_suffixes] || {}).each do |param, template|
          value = args[param.to_s]
          next unless present?(value)

          input += interpolate_suffix(template.to_s, value)
          appended = true
        end
        # A tool may declare the grammar a BARE call means (`bare_input:`) —
        # e.g. pito_analyze with no noun/ref documents itself as "all your
        # channels", which is the `analyze channels` form, NOT bare `analyze`
        # (that one just asks what to analyze). Only when no suffix fired.
        input = interpolate(descriptor[:bare_input].to_s, args) if !appended && descriptor[:bare_input]
        input.strip
      end

      def interpolate(template, args)
        template.gsub(/%\{(\w+)\}/) { format_value(args[Regexp.last_match(1)]) }
      end

      def interpolate_suffix(template, value)
        template.gsub("%{values}", join_values(value)).gsub("%{value}", format_value(value))
      end

      def format_value(value)
        value.is_a?(Array) ? join_values(value) : value.to_s
      end

      def join_values(value)
        Array(value).map(&:to_s).join(", ")
      end

      # Declared params that are NOT interpolated into the grammar (neither an input
      # placeholder nor an input_suffixes key) are forwarded to Router.call — but
      # only the ones Router actually accepts (ROUTER_FORWARDABLE).
      def router_kwargs(descriptor, args)
        interpolated = input_placeholders(descriptor) | (descriptor[:input_suffixes] || {}).keys.map(&:to_s)
        forwarded    = (descriptor[:params] || {}).keys.map(&:to_s) - interpolated

        forwarded.each_with_object({}) do |name, kwargs|
          sym = name.to_sym
          kwargs[sym] = args[name] if ROUTER_FORWARDABLE.include?(sym) && present?(args[name])
        end
      end

      def input_placeholders(descriptor)
        descriptor[:input].to_s.scan(/%\{(\w+)\}/).flatten
      end

      # ── validation ─────────────────────────────────────────────────────────────

      def missing_required(descriptor, args)
        (descriptor[:params] || {}).filter_map do |name, spec|
          name.to_s if spec[:required] && !present?(args[name.to_s])
        end
      end

      def missing_message(missing)
        "Missing required argument#{missing.size > 1 ? 's' : ''}: #{missing.join(', ')}."
      end

      # Reject unknown values at the MCP boundary rather than letting the
      # chatbox grammar silently drop them: `enum` params (e.g. noun) are checked
      # against their allowlist, and a `capability: columns` param against the ACTUAL
      # noun's real column set from Pito::Grammar::Capability. `filter`/`sort` stay
      # lenient (genre/platform values + sort directions are open) — matching the
      # chatbox, which is deliberately forgiving; the MCP surface only hardens the
      # closed sets. Returns a list of human-readable error lines ([] when clean).
      def validation_errors(descriptor, args)
        verb = descriptor[:verb]
        noun = args["noun"].to_s

        (descriptor[:params] || {}).flat_map do |name, spec|
          value = args[name.to_s]
          next [] unless present?(value)

          if spec[:enum]
            enum_errors(name, value, spec[:enum].map(&:to_s))
          elsif spec[:capability].to_s == "columns" && verb.present?
            column_errors(value, verb, noun)
          else
            []
          end
        end
      end

      def enum_errors(name, value, allowed)
        Array(value).map(&:to_s).reject { |v| allowed.include?(v) }
                    .map { |bad| %(Unknown #{name} "#{bad}". Valid: #{allowed.join(', ')}.) }
      end

      # Validate column tokens against the noun's real (public) column vocabulary.
      # Skipped when the noun resolves to no columns (an invalid noun is already
      # reported by its own enum check, so this avoids a confusing double error).
      def column_errors(value, verb, noun)
        vocab = Pito::Grammar::Capability.column_vocabulary(verb.to_sym, noun)
        return [] if vocab.empty?

        valid = Pito::Grammar::Capability.public_columns(verb.to_sym, noun).map(&:name)
        Array(value).map(&:to_s).reject { |v| vocab.key?(v.downcase) }
                    .map { |bad| %(Unknown column "#{bad}" for #{noun}. Valid columns: #{valid.join(', ')}.) }
      end

      # ── helpers ────────────────────────────────────────────────────────────────

      def error?(result)
        result.is_a?(Pito::Chat::Result::Error)
      end

      def present?(value)
        return false if value.nil?
        return value.any? if value.is_a?(Array)

        !value.to_s.strip.empty?
      end

      def stringify(arguments)
        (arguments || {}).to_h.transform_keys(&:to_s)
      end

      # The persisted anchor Conversation the Router dispatches against — some
      # handlers need a real conversation id (handle minting, scope/period state).
      # Its EVENTS are never persisted (MCP bypasses the dispatch jobs), and it is
      # a dedicated `source: "mcp"` row so it never leaks into the app scrollback,
      # the resume sidebar, or the auto-purge (Conversation.mcp_anchor).
      def mcp_conversation
        ::Conversation.mcp_anchor
      end
    end
  end
end
