# frozen_string_literal: true

module Pito
  module Dispatch
    # Cached loader for config/pito/tools.yml — the tool ontology.
    #
    # Loads + deep-freezes the YAML once per boot; memoized at the class level.
    # In development, Rails.application.config.to_prepare triggers .reload! so
    # the file is re-read on each request cycle (wired in
    # config/initializers/pito_dispatch_config.rb).
    #
    # Public API:
    #   Pito::Dispatch::Config.tool(:list)        # => frozen Hash, symbol keys
    #   Pito::Dispatch::Config.pager(tool: :list) # => { page_size: 50, more_tool: "next" } | nil
    #   Pito::Dispatch::Config.reload!            # clears memoization (used in dev + tests)
    #
    # Raises LoadError at first access if the file is missing or the
    # schema_version is unsupported — config rot fails boot, not silently.
    module Config
      SUPPORTED_SCHEMA_VERSIONS = [ 1 ].freeze
      PATH = Rails.root.join("config/pito/tools.yml")

      module_function

      # Returns the frozen tool Hash for +name+ (symbol or string), symbol-keyed.
      # Raises KeyError for unknown tools.
      def tool(name)
        data.fetch(:tools, {}).fetch(name.to_sym) do
          raise KeyError, "Pito::Dispatch::Config: unknown tool #{name.inspect}"
        end
      end

      # Returns the pager concern Hash for +tool+, or nil when the tool declares no pager.
      def pager(tool:)
        tool(tool).dig(:concerns, :pager)
      end

      # The hard ceiling for client-supplied page sizes on +tool+'s cursor
      # feeds (viewport-driven clients send their visible-row count as
      # `limit`; the server clamps to this). Falls back to the declared
      # page_size when the pager sets no explicit cap; nil when the tool
      # has no pager at all.
      def max_page_size(tool:)
        p = pager(tool: tool)
        p && (p[:max_page_size] || p[:page_size])
      end

      # The natural-language phrasing corpus declared on +tool+'s `nl_examples:`
      # key, or [] when the tool declares none. One ontology, three consumers:
      # the NL router embeds these to route free-text chat, the MCP tool
      # descriptions surface them to a client model, and the mapper's few-shot
      # prompt reads them as worked examples — so the phrasings never drift
      # between the three.
      def nl_examples(tool:)
        tool(tool)[:nl_examples] || []
      end

      # The top-level `nl:` block's confidence thresholds ({ auto_run:, suggest: },
      # both Floats 0..1), or {} when the document declares none. One ontology,
      # shared by the router: below `suggest` a free-text guess is dropped, at or
      # above it the router surfaces a confirmation, at or above `auto_run` it
      # dispatches without asking.
      def nl_thresholds
        data[:nl]&.dig(:thresholds) || {}
      end

      # The top-level `nl:` block's synonym map ({ word => canonical }, both
      # Strings), or {} when the document declares none. The router folds a
      # chatting owner's word choice into its canonical token before matching.
      def nl_synonyms
        data[:nl]&.dig(:synonyms) || {}
      end

      # The top-level `nl:` block's exemplar corpus ([{ say:, run: }, …]), or []
      # when the document declares none. One ontology, authored once: the
      # mapper retrieval-picks from these say → run pairs for its few-shot
      # prompt (distinct from the per-tool nl_examples: above — those are a
      # single tool's phrasings, these are the whole ontology's worked examples).
      def nl_exemplars
        data[:nl]&.dig(:exemplars) || []
      end

      # Clears memoization so the next access reloads from disk.
      def reload!
        @data = nil
      end

      # Returns the memoized, deep-frozen parsed YAML document.
      def data
        @data ||= load!
      end

      # ── Private ───────────────────────────────────────────────────────────────

      def load!
        raise LoadError, "Pito::Dispatch::Config: #{PATH} not found" unless PATH.exist?

        raw = YAML.safe_load_file(PATH, symbolize_names: true)
        version = raw[:schema_version]

        unless SUPPORTED_SCHEMA_VERSIONS.include?(version)
          raise LoadError,
                "Pito::Dispatch::Config: unsupported schema_version #{version.inspect} " \
                "(supported: #{SUPPORTED_SCHEMA_VERSIONS.inspect})"
        end

        deep_freeze(raw)
      end

      def deep_freeze(obj)
        case obj
        when Hash  then obj.transform_values { |v| deep_freeze(v) }.freeze
        when Array then obj.map { |v| deep_freeze(v) }.freeze
        else            obj.frozen? ? obj : obj.freeze
        end
      end
    end
  end
end
