# frozen_string_literal: true

module Pito
  module Achievements
    # Cached loader for config/pito/shinies.yml — the shinies ontology
    # (mirrors Pito::Dispatch::Config, the tools.yml loader).
    #
    # Loads + deep-freezes the YAML once per boot; memoized at the class
    # level. In development, config.to_prepare triggers .reload! so edits are
    # picked up per request cycle (config/initializers/pito_shinies_config.rb).
    #
    # Public API:
    #   Config.ceilings                    # => { "Video" => { "views" => 1_000_000, … }, … }
    #   Config.awards                      # => { 100_000 => "silver", … } (ascending)
    #   Config.metrics_for("Channel")      # => %w[views watched_hours likes comments subs]
    #   Config.reload!                     # clears memoization (dev + tests)
    #
    # Raises LoadError at first access when the file is missing, the
    # schema_version is unsupported, or the shape is invalid — a self-hoster's
    # broken custom mount fails boot loudly, never silently mis-shines.
    module Config
      SUPPORTED_SCHEMA_VERSIONS = [ 1 ].freeze
      PATH = Rails.root.join("config/pito/shinies.yml")

      # yml scope key → polymorphic_name, fixed: scopes ARE the product's
      # domain triad, not a customization surface.
      SCOPES = { video: "Video", game: "Game", channel: "Channel" }.freeze

      # The metric universe the achievements pipeline can feed (the refresh
      # job writes exactly these keys) — a typo'd metric must fail boot, not
      # sit as a ladder nothing ever climbs.
      KNOWN_METRICS = %w[subs subs_gained views watched_hours likes comments].freeze

      module_function

      # Stone-ladder ceilings keyed by polymorphic scope name.
      # @return [Hash{String => Hash{String => Integer}}] frozen
      def ceilings
        data.fetch(:ceilings)
      end

      # Channel-subs award thresholds → metal name, ascending.
      # @return [Hash{Integer => String}] frozen
      def awards
        data.fetch(:awards)
      end

      # The valid metric list for a polymorphic scope name — derived from the
      # configured ceiling keys, so the yml stays the single source of truth.
      # @return [Array<String>] frozen ([] for unknown scopes)
      def metrics_for(scope)
        ceilings.fetch(scope.to_s, {}).keys
      end

      # Clears memoization so the next access reloads from disk.
      def reload!
        @data = nil
      end

      def data
        @data ||= load!
      end

      # ── Private ─────────────────────────────────────────────────────────────

      def load!
        raise LoadError, "Pito::Achievements::Config: #{PATH} not found" unless PATH.exist?

        raw = YAML.safe_load_file(PATH, symbolize_names: true)
        version = raw[:schema_version]
        unless SUPPORTED_SCHEMA_VERSIONS.include?(version)
          raise LoadError,
                "Pito::Achievements::Config: unsupported schema_version #{version.inspect} " \
                "(supported: #{SUPPORTED_SCHEMA_VERSIONS.inspect})"
        end

        {
          ceilings: validated_ceilings(raw[:ceilings]),
          awards:   validated_awards(raw[:awards])
        }.freeze
      end

      def validated_ceilings(raw)
        raise LoadError, "Pito::Achievements::Config: ceilings must map #{SCOPES.keys.inspect}" unless raw.is_a?(Hash)

        unknown = raw.keys - SCOPES.keys
        missing = SCOPES.keys - raw.keys
        raise LoadError, "Pito::Achievements::Config: unknown ceiling scope(s) #{unknown.inspect}" if unknown.any?
        raise LoadError, "Pito::Achievements::Config: missing ceiling scope(s) #{missing.inspect}" if missing.any?

        SCOPES.to_h { |key, scope| [ scope, validated_metrics(key, raw[key]) ] }.freeze
      end

      def validated_metrics(scope_key, metrics)
        unless metrics.is_a?(Hash) && metrics.any?
          raise LoadError, "Pito::Achievements::Config: ceilings.#{scope_key} must list at least one metric"
        end

        metrics.to_h do |metric, ceiling|
          name = metric.to_s
          unless KNOWN_METRICS.include?(name)
            raise LoadError,
                  "Pito::Achievements::Config: unknown metric #{name.inspect} under ceilings.#{scope_key} " \
                  "(known: #{KNOWN_METRICS.inspect})"
          end
          unless ceiling.is_a?(Integer) && ceiling.positive?
            raise LoadError,
                  "Pito::Achievements::Config: ceilings.#{scope_key}.#{name} must be a positive integer " \
                  "(got #{ceiling.inspect})"
          end
          [ name, ceiling ]
        end.freeze
      end

      def validated_awards(raw)
        raise LoadError, "Pito::Achievements::Config: awards must map metal => threshold" unless raw.is_a?(Hash)

        thresholds = raw.values
        unless thresholds.all? { |t| t.is_a?(Integer) && t.positive? }
          raise LoadError, "Pito::Achievements::Config: award thresholds must be positive integers"
        end
        unless thresholds == thresholds.sort && thresholds.uniq == thresholds
          raise LoadError, "Pito::Achievements::Config: award thresholds must strictly ascend"
        end

        raw.to_h { |metal, threshold| [ threshold, metal.to_s ] }.freeze
      end
    end
  end
end
