# frozen_string_literal: true

module Pito
  module Mcp
    # Runs one MCP tool call. For a verb-backed tool it builds a chat GRAMMAR string
    # from the tool's `input` template + `input_suffixes` (the same grammar a human
    # types), routes it through the UNMODIFIED Pito::Dispatch::Router, and projects
    # the Result's events to markdown via EventText — so the server's grammar stays
    # the single behaviour authority and MCP adds no parallel logic.
    #
    # READ-ONLY, NON-PERSISTING by construction: Router.call returns handler Results
    # and writes nothing; persistence lives in the dispatch JOBS, which MCP never
    # invokes. This class must never create/update/enqueue (the one allowed write —
    # the anchor Conversation — is minted by #mcp_conversation, see T2.5). The spec
    # proves Event.count is unchanged across a call.
    #
    # Pending analytics (analyze / breakdowns / glance / channels) normally fill via
    # jobs + Turbo; MCP is pull-only, so the Executor computes them INLINE — that is
    # T2.3, wired into #fill_pending. Errors (Result::Error) render through EventText
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

      # ── verb-backed tools ──────────────────────────────────────────────────────

      def execute_verb(descriptor, args)
        missing = missing_required(descriptor, args)
        return Result.new(text: missing_message(missing), is_error: true) if missing.any?

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
        input = interpolate(descriptor[:input].to_s, args)
        (descriptor[:input_suffixes] || {}).each do |param, template|
          value = args[param.to_s]
          next unless present?(value)

          input += interpolate_suffix(template.to_s, value)
        end
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
