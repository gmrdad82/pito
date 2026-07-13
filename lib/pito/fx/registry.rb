# frozen_string_literal: true

module Pito
  module Fx
    # Cached, validating loader for config/pito/fx.yml — the living
    # background's ontology (engine knobs, effects, context → { covers,
    # weighted pool }).
    #
    # Mirrors the Pito::Dispatch::Config discipline: loads + deep-freezes the
    # YAML once per boot, memoized at the class level; `reload!` clears the
    # memo (dev request cycle + specs). Validation fails LOUDLY at first
    # access — config rot fails boot, not silently — with did-you-mean hints
    # in the Pito::Dispatch::Schema voice.
    #
    # THE COMPATIBILITY GUARD (owner law): a context's `covers:` is what it
    # CARRIES (single | many | none). A pool entry's effect may only demand
    # what the context actually has — `single` effects only in `single`
    # contexts, `many` effects only in `many` contexts, `none` effects
    # anywhere. Water on a list is a BOOT ERROR, not a silent skip.
    #
    # Public API:
    #   Pito::Fx::Registry.engine            # => frozen Hash (fps, dpr_cap, …)
    #   Pito::Fx::Registry.effects           # => frozen Hash of effect defs
    #   Pito::Fx::Registry.pool(:game_detail)# => frozen Array of {effect:, weight:}
    #   Pito::Fx::Registry.contexts          # => frozen Hash of {covers:, pool:}
    #   Pito::Fx::Registry.as_json           # => plain Hash for the JS engine
    #   Pito::Fx::Registry.reload!
    class Registry
      SCHEMA_VERSION = 2
      PATH = Rails.root.join("config/pito/fx.yml")

      TOP_KEYS          = %w[schema_version engine effects contexts].freeze
      ENGINE_KEYS        = %w[fps dpr_cap crossfade_ms hysteresis_ms enforcer_alpha butterflies ring_idle_ms].freeze
      EFFECT_KEYS        = %w[engine covers needs_float tint_source knobs].freeze
      EFFECT_REQUIRED_KEYS = %w[engine covers needs_float tint_source].freeze
      CONTEXT_KEYS       = %w[covers pool].freeze
      POOL_KEYS          = %w[effect weight].freeze
      ENGINES            = %w[css canvas webgl].freeze
      TINT_SOURCES       = %w[theme cover fixed].freeze
      COVERAGES          = %w[single many none].freeze

      class Invalid < StandardError; end

      class << self
        def engine   = data.fetch(:engine)
        def effects  = data.fetch(:effects)
        def contexts = data.fetch(:contexts)

        # The weighted pool for +context+ (symbol or string); the `default`
        # pool when the context is unknown (F1: sky is the no-fit answer).
        def pool(context)
          contexts.fetch(context.to_sym) { contexts.fetch(:default) }.fetch(:pool)
        end

        # Plain, JSON-ready Hash for the JS engine (served once per page).
        def as_json
          { engine: engine, effects: effects, contexts: contexts }
        end

        def reload!
          @data = nil
        end

        private

        def data
          @data ||= load!
        end

        def load!
          raise Invalid, "#{PATH} is missing" unless File.exist?(PATH)

          raw = YAML.safe_load_file(PATH, aliases: false)
          errors = validate(raw)
          raise Invalid, "config/pito/fx.yml invalid:\n  - #{errors.join("\n  - ")}" if errors.any?

          data = deep_symbolize(raw.except("schema_version"))
          # Normalize pool effect REFERENCES to symbols so consumers join
          # pool entries onto `effects` (symbol-keyed) without casts.
          data[:contexts] = data[:contexts].transform_values do |context|
            context.merge(pool: context[:pool].map { |entry| entry.merge(effect: entry[:effect].to_sym) })
          end
          deep_freeze(data)
        end

        def validate(raw)
          errors = []
          return [ "top level must be a mapping" ] unless raw.is_a?(Hash)

          unless raw["schema_version"] == SCHEMA_VERSION
            errors << "schema_version #{raw['schema_version'].inspect} unsupported (expected #{SCHEMA_VERSION})"
          end

          (raw.keys - TOP_KEYS).each do |key|
            errors << "unknown top-level key #{key.inspect}#{did_you_mean(key, TOP_KEYS)}"
          end

          validate_engine(raw["engine"], errors)
          effects = validate_effects(raw["effects"], errors)
          validate_contexts(raw["contexts"], effects, errors)
          errors
        end

        def validate_engine(engine, errors)
          return errors << "`engine` must be a mapping" unless engine.is_a?(Hash)

          (engine.keys - ENGINE_KEYS).each do |key|
            errors << "engine: unknown key #{key.inspect}#{did_you_mean(key, ENGINE_KEYS)}"
          end
          ENGINE_KEYS.each do |key|
            value = engine[key]
            errors << "engine.#{key} must be a positive number (got #{value.inspect})" unless value.is_a?(Numeric) && value.positive?
          end
        end

        def validate_effects(effects, errors)
          return errors << "`effects` must be a non-empty mapping" && {} unless effects.is_a?(Hash) && effects.any?

          effects.each do |name, definition|
            path = "effects.#{name}"
            unless definition.is_a?(Hash)
              errors << "#{path} must be a mapping"
              next
            end

            if definition.key?("needs_cover")
              errors << "#{path}: needs_cover is gone — declare `covers:` (single|many|none) instead"
            end

            (definition.keys - [ "needs_cover" ] - EFFECT_KEYS).each do |key|
              errors << "#{path}: unknown key #{key.inspect}#{did_you_mean(key, EFFECT_KEYS)}"
            end
            (EFFECT_REQUIRED_KEYS - definition.keys).each do |key|
              errors << "#{path}: missing key #{key.inspect}"
            end

            if definition.key?("knobs")
              knobs = definition["knobs"]
              if knobs.is_a?(Hash) && knobs.any?
                knobs.each do |k, v|
                  errors << "#{path}.knobs.#{k} must be a number (got #{v.inspect})" unless v.is_a?(Numeric)
                end
              else
                errors << "#{path}.knobs must be a non-empty mapping of numeric tunables"
              end
            end

            unless ENGINES.include?(definition["engine"])
              errors << "#{path}.engine #{definition['engine'].inspect} unknown#{did_you_mean(definition['engine'], ENGINES)} (allowed: #{ENGINES.join(', ')})"
            end
            unless COVERAGES.include?(definition["covers"])
              errors << "#{path}.covers #{definition['covers'].inspect} unknown#{did_you_mean(definition['covers'], COVERAGES)} (allowed: #{COVERAGES.join(', ')})"
            end
            unless TINT_SOURCES.include?(definition["tint_source"])
              errors << "#{path}.tint_source #{definition['tint_source'].inspect} unknown#{did_you_mean(definition['tint_source'], TINT_SOURCES)} (allowed: #{TINT_SOURCES.join(', ')})"
            end
            value = definition["needs_float"]
            errors << "#{path}.needs_float must be true or false (got #{value.inspect})" unless [ true, false ].include?(value)
          end
          effects
        end

        def validate_contexts(contexts, effects, errors)
          return errors << "`contexts` must be a non-empty mapping" unless contexts.is_a?(Hash) && contexts.any?

          errors << "contexts must declare `default` (the sky fallback)" unless contexts.key?("default")

          contexts.each do |name, definition|
            path = "contexts.#{name}"
            unless definition.is_a?(Hash)
              errors << "#{path} must be a mapping with `covers` and `pool`"
              next
            end

            (definition.keys - CONTEXT_KEYS).each do |key|
              errors << "#{path}: unknown key #{key.inspect}#{did_you_mean(key, CONTEXT_KEYS)}"
            end
            (CONTEXT_KEYS - definition.keys).each do |key|
              errors << "#{path}: missing key #{key.inspect}"
            end

            context_covers = definition["covers"]
            unless COVERAGES.include?(context_covers)
              errors << "#{path}.covers #{context_covers.inspect} unknown#{did_you_mean(context_covers, COVERAGES)} (allowed: #{COVERAGES.join(', ')})"
            end

            validate_pool(path, definition["pool"], context_covers, effects, errors)
          end
        end

        def validate_pool(path, pool, context_covers, effects, errors)
          unless pool.is_a?(Array) && pool.any?
            errors << "#{path}.pool must be a non-empty list of {effect, weight}"
            return
          end

          pool.each_with_index do |entry, i|
            entry_path = "#{path}.pool[#{i}]"
            unless entry.is_a?(Hash)
              errors << "#{entry_path} must be a {effect, weight} mapping"
              next
            end

            (entry.keys - POOL_KEYS).each do |key|
              errors << "#{entry_path}: unknown key #{key.inspect}#{did_you_mean(key, POOL_KEYS)}"
            end

            effect_name = entry["effect"]
            effect_definition = effects.is_a?(Hash) ? effects[effect_name] : nil
            unless effect_definition
              errors << "#{entry_path}.effect #{effect_name.inspect} is not a declared effect#{did_you_mean(effect_name, effects.is_a?(Hash) ? effects.keys : [])}"
            end

            weight = entry["weight"]
            errors << "#{entry_path}.weight must be a positive number (got #{weight.inspect})" unless weight.is_a?(Numeric) && weight.positive?

            next unless effect_definition && COVERAGES.include?(context_covers)

            effect_covers = effect_definition["covers"]
            next unless COVERAGES.include?(effect_covers)
            next if effect_covers == "none" || effect_covers == context_covers

            errors << "#{path}: effect #{effect_name.inspect} needs covers: #{effect_covers} but this context carries " \
                       "covers: #{context_covers} — #{coverage_mismatch_reason(effect_covers, context_covers)} (owner law)"
          end
        end

        # Human-readable reason for THE COMPATIBILITY GUARD violation, in the
        # owner's own voice (see fx.yml header + OWNER LOCKS comment).
        def coverage_mismatch_reason(effect_covers, context_covers)
          case [ effect_covers, context_covers ]
          when [ "single", "many" ] then "single-cover moods never render lists"
          when [ "single", "none" ] then "single-cover moods need art to wear"
          when [ "many", "single" ] then "cover-wall moods never render single-entity moments"
          when [ "many", "none" ] then "cover-wall moods need art to wear"
          else "cover cardinality mismatch"
          end
        end

        # Nearest-candidate hint in the Pito::Dispatch::Schema voice.
        def did_you_mean(value, allowed)
          hint = DidYouMean::SpellChecker.new(dictionary: allowed.map(&:to_s)).correct(value.to_s).first
          hint ? " (did you mean #{hint}?)" : ""
        end

        def deep_symbolize(value)
          case value
          when Hash  then value.to_h { |k, v| [ k.to_sym, deep_symbolize(v) ] }
          when Array then value.map { |v| deep_symbolize(v) }
          else value
          end
        end

        def deep_freeze(value)
          case value
          when Hash  then value.each_value { |v| deep_freeze(v) }.freeze
          when Array then value.each { |v| deep_freeze(v) }.freeze
          else value.freeze
          end
        end
      end
    end
  end
end
