# frozen_string_literal: true

class Game
  module Traits
    # Cached loader for config/pito/traits.yml — the owner's game-trait
    # vocabulary (mirrors Pito::Dispatch::Config, the tools.yml loader, and
    # Pito::Achievements::Config, the shinies.yml loader — same memoize /
    # deep-freeze / to_prepare-reload shape).
    #
    # ONE deliberate difference from those two: loaded WITHOUT
    # `symbolize_names` — this vocabulary validates the string-keyed
    # `games.traits` jsonb column, so every name it hands back (scale names,
    # tag names, scale values) stays a String end to end. Only this module's
    # OWN internal wrapping hash (`data[:scales]` / `data[:tags]`) uses
    # symbol keys, exactly like Achievements::Config's `data[:ceilings]`.
    #
    # Build contract: traits-design.md section 2.
    #
    # Public API:
    #   Vocabulary.scales                          # {"difficulty"=>{"values"=>[...], "description"=>..., "source"=>"classified"}, ...}
    #   Vocabulary.tags                            # {"space"=>{"source"=>"classified", "description"=>...}, ...}
    #   Vocabulary.scale_names                     # ["difficulty", "story", "pace"] (declaration order)
    #   Vocabulary.tag_names                       # declaration order
    #   Vocabulary.derived_tag_names                # tags with source: derived
    #   Vocabulary.classified_tag_names              # tags with source: classified
    #   Vocabulary.valid_scale_value?(scale, value)  # => bool
    #   Vocabulary.errors_for(traits_hash)           # => [String] ([] = valid)
    #   Vocabulary.reload!                           # clears memoization (dev + tests)
    #
    # Raises LoadError at first access when the file is missing, the
    # schema_version is unsupported, a name is declared in BOTH `scales:`
    # and `tags:` (the flat `sources` map couldn't disambiguate which one a
    # write meant), or a scale is named "tags" (reserved by the
    # `values.tags` array shape) — config rot fails boot, never a silent
    # mis-classify.
    module Vocabulary
      SUPPORTED_SCHEMA_VERSIONS = [ 1 ].freeze
      PATH = Rails.root.join("config/pito/traits.yml")

      # The only legal values a `sources` entry may hold.
      VALID_SOURCES = %w[owner classified derived].freeze

      # The closed set of top-level keys a non-empty games.traits jsonb hash
      # may carry (traits-design.md section 1) — anything else is typo rot.
      TOP_LEVEL_KEYS = %w[schema_version values sources classified_at].freeze

      module_function

      # The scale ontology, keyed by scale name, declaration order.
      # @return [Hash{String => Hash}] frozen
      def scales
        data[:scales]
      end

      # The tag ontology, keyed by tag name, declaration order.
      # @return [Hash{String => Hash}] frozen
      def tags
        data[:tags]
      end

      # @return [Array<String>] declared scale names, in file order
      def scale_names
        scales.keys
      end

      # @return [Array<String>] declared tag names, in file order
      def tag_names
        tags.keys
      end

      # @return [Array<String>] tag names whose vocabulary source is derived
      def derived_tag_names
        tags.select { |_name, meta| meta["source"] == "derived" }.keys
      end

      # @return [Array<String>] tag names whose vocabulary source is classified
      def classified_tag_names
        tags.select { |_name, meta| meta["source"] == "classified" }.keys
      end

      # @return [Boolean] whether +value+ is a declared member of +scale+'s
      #   values list. false (never raises) for an unknown scale.
      def valid_scale_value?(scale, value)
        Array(scales.dig(scale.to_s, "values")).include?(value)
      end

      # THE validator for the games.traits jsonb shape (traits-design.md
      # section 1/2) — reused by the model validation
      # (Game#traits_conform_to_vocabulary) and the classify import
      # (pito:traits:import), so both surfaces report identical messages for
      # identical mistakes.
      #
      # @param traits [Object] a candidate games.traits value
      # @return [Array<String>] human-readable problems; [] means valid
      def errors_for(traits)
        return [ "must be a Hash" ] unless traits.is_a?(Hash)
        return [] if traits.empty?

        errors = top_level_key_errors(traits) + schema_version_errors(traits)

        values  = hash_or(traits, "values", errors)
        sources = hash_or(traits, "sources", errors)

        tag_list = tag_list_for(values, errors)
        errors.concat(scale_value_errors(values))
        errors.concat(sources_errors(sources, values, tag_list))
        errors
      end

      # Clears memoization so the next access reloads from disk.
      def reload!
        @data = nil
      end

      # The memoized, deep-frozen parsed vocabulary.
      def data
        @data ||= load!
      end

      # ── Private ─────────────────────────────────────────────────────────

      def load!
        raise LoadError, "Game::Traits::Vocabulary: #{PATH} not found" unless PATH.exist?

        raw = YAML.safe_load_file(PATH)
        version = raw["schema_version"]
        unless SUPPORTED_SCHEMA_VERSIONS.include?(version)
          raise LoadError,
                "Game::Traits::Vocabulary: unsupported schema_version #{version.inspect} " \
                "(supported: #{SUPPORTED_SCHEMA_VERSIONS.inspect})"
        end

        scales_data = raw["scales"] || {}
        tags_data   = raw["tags"] || {}

        overlap = scales_data.keys & tags_data.keys
        if overlap.any?
          raise LoadError,
                "Game::Traits::Vocabulary: name(s) declared in both scales: and tags: — #{overlap.sort.inspect}"
        end

        if scales_data.key?("tags")
          raise LoadError,
                "Game::Traits::Vocabulary: a scale cannot be named \"tags\" (reserved by the values.tags shape)"
        end

        { scales: deep_freeze(scales_data), tags: deep_freeze(tags_data) }.freeze
      end

      def deep_freeze(obj)
        case obj
        when Hash  then obj.transform_values { |v| deep_freeze(v) }.freeze
        when Array then obj.map { |v| deep_freeze(v) }.freeze
        else            obj.frozen? ? obj : obj.freeze
        end
      end

      # Reads +key+ off +traits+ as a Hash, defaulting a missing/nil value to
      # {} (values/sources "may be absent; readers treat absence like {}").
      # A present-but-non-Hash value pushes an error onto +errors+ and is
      # also treated as absent for the rest of validation.
      def hash_or(traits, key, errors)
        raw = traits[key]
        return {} if raw.nil?
        return raw if raw.is_a?(Hash)

        errors << "#{key} must be a Hash"
        {}
      end

      def top_level_key_errors(traits)
        unknown = traits.keys - TOP_LEVEL_KEYS
        unknown.any? ? [ "unknown top-level key(s): #{unknown.sort.inspect}" ] : []
      end

      def schema_version_errors(traits)
        version = traits["schema_version"]
        return [] if SUPPORTED_SCHEMA_VERSIONS.include?(version)

        [ "unsupported schema_version #{version.inspect} (supported: #{SUPPORTED_SCHEMA_VERSIONS.inspect})" ]
      end

      # Validates values["tags"] (shape + membership + duplicates) and
      # returns the usable list (falling back to [] on a shape error, so
      # downstream sources-legality checks have something to check absence
      # against instead of raising).
      def tag_list_for(values, errors)
        return [] unless values.key?("tags")

        list = values["tags"]
        unless list.is_a?(Array)
          errors << "values.tags must be an Array"
          return []
        end

        unknown = list - tag_names
        errors << "unknown tag(s) in values.tags: #{unknown.sort.inspect}" if unknown.any?

        dupes = list.tally.select { |_name, count| count > 1 }.keys
        errors << "duplicate tag(s) in values.tags: #{dupes.sort.inspect}" if dupes.any?

        list
      end

      def scale_value_errors(values)
        (values.keys - [ "tags" ]).filter_map do |scale|
          next "unknown scale #{scale.inspect} in values" unless scale_names.include?(scale)
          next if valid_scale_value?(scale, values[scale])

          "#{values[scale].inspect} is not a valid value for scale #{scale.inspect} " \
            "(allowed: #{scales[scale]['values'].inspect})"
        end
      end

      def sources_errors(sources, values, tag_list)
        sources.flat_map { |name, source| source_errors_for(name, source, values, tag_list) }
      end

      def source_errors_for(name, source, values, tag_list)
        kind = trait_kind(name)
        return [ "unknown trait #{name.inspect} in sources" ] if kind.nil?

        unless VALID_SOURCES.include?(source)
          return [ "invalid source #{source.inspect} for #{name.inspect} (allowed: #{VALID_SOURCES.inspect})" ]
        end

        declared_source = kind == :scale ? scales[name]["source"] : tags[name]["source"]
        legal = declared_source == "derived" ? %w[derived owner] : %w[classified owner]
        unless legal.include?(source)
          return [ "source #{source.inspect} not legal for #{name.inspect} " \
                   "(#{declared_source}-declared; allowed: #{legal.inspect})" ]
        end

        present = kind == :scale ? values.key?(name) : tag_list.include?(name)
        return [] if present || source == "owner"

        [ "sources[#{name.inspect}] = #{source.inspect} but #{name.inspect} is absent from values " \
          "(only \"owner\" may pin absence)" ]
      end

      def trait_kind(name)
        return :scale if scale_names.include?(name)
        return :tag if tag_names.include?(name)

        nil
      end
    end
  end
end
