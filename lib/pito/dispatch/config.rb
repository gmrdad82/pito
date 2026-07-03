# frozen_string_literal: true

module Pito
  module Dispatch
    # Cached loader for config/pito/verbs.yml — the D7 verb ontology.
    #
    # Loads + deep-freezes the YAML once per boot; memoized at the class level.
    # In development, Rails.application.config.to_prepare triggers .reload! so
    # the file is re-read on each request cycle (wired in
    # config/initializers/pito_dispatch_config.rb).
    #
    # Public API:
    #   Pito::Dispatch::Config.verb(:list)        # => frozen Hash, symbol keys
    #   Pito::Dispatch::Config.pager(verb: :list) # => { page_size: 50, more_verb: "next" } | nil
    #   Pito::Dispatch::Config.reload!            # clears memoization (used in dev + tests)
    #
    # Raises LoadError at first access if the file is missing or the
    # schema_version is unsupported — config rot fails boot, not silently.
    module Config
      SUPPORTED_SCHEMA_VERSIONS = [ 1 ].freeze
      PATH = Rails.root.join("config/pito/verbs.yml")

      module_function

      # Returns the frozen verb Hash for +name+ (symbol or string), symbol-keyed.
      # Raises KeyError for unknown verbs.
      def verb(name)
        data.fetch(:verbs, {}).fetch(name.to_sym) do
          raise KeyError, "Pito::Dispatch::Config: unknown verb #{name.inspect}"
        end
      end

      # Returns the pager concern Hash for +verb+, or nil when the verb declares no pager.
      def pager(verb:)
        verb(verb).dig(:concerns, :pager)
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
