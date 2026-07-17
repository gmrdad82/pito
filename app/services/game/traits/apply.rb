# frozen_string_literal: true

class Game
  module Traits
    # THE write path for `games.traits` (traits-design.md section 4) — the
    # ONLY place that mutates the column. Every writer (the classify import,
    # Game::Traits::Derive, any future chat surface) goes through `call`;
    # nothing else touches games.traits directly.
    module Apply
      VALID_SOURCES = %w[owner classified derived].freeze

      module_function

      # @param game [Game]
      # @param source [String] "owner" | "classified" | "derived"
      # @param scales [Hash{String,Symbol => String,nil}] scale name => new
      #   value; a nil value REMOVES that scale.
      # @param add_tags [Array<String,Symbol>] tag names to set present
      # @param remove_tags [Array<String,Symbol>] tag names to set absent
      # @return [Hash] { changed: Boolean, skipped_owner: [String] } —
      #   skipped_owner lists every name this call could not touch because
      #   an existing "owner" source locked it (source != "owner" only).
      # @raise [Pito::Error::TraitInvalid] on an unknown name, an
      #   out-of-vocabulary scale value, a name in both add_tags and
      #   remove_tags, or a source illegal for a name's declared kind.
      def call(game:, source:, scales: {}, add_tags: [], remove_tags: [])
        scales = scales.transform_keys(&:to_s)
        add_tags = add_tags.map(&:to_s)
        remove_tags = remove_tags.map(&:to_s)

        validate!(game: game, source: source, scales: scales, add_tags: add_tags, remove_tags: remove_tags)

        values = (game.traits["values"] || {}).deep_dup
        sources = (game.traits["sources"] || {}).deep_dup
        original_values = values.deep_dup
        original_sources = sources.deep_dup
        tag_list = Array(values["tags"]).dup

        skipped_owner = apply_scales(values, sources, scales, source)
        skipped_owner += apply_add_tags(tag_list, sources, add_tags, source)
        skipped_owner += apply_remove_tags(tag_list, sources, remove_tags, source)

        normalize_tags!(values, tag_list)

        changed = values != original_values || sources != original_sources
        return { changed: false, skipped_owner: skipped_owner } unless changed

        persist!(game, values, sources, source)
        { changed: true, skipped_owner: skipped_owner }
      end

      # ── Per-collection application (returns the names skipped as owner-locked) ──

      def apply_scales(values, sources, scales, source)
        scales.filter_map do |name, value|
          next name if owner_locked?(sources, name, source)

          apply_scale(values, sources, name, value, source)
          nil
        end
      end

      def apply_add_tags(tag_list, sources, add_tags, source)
        add_tags.filter_map do |tag|
          next tag if owner_locked?(sources, tag, source)

          tag_list << tag unless tag_list.include?(tag)
          sources[tag] = source
          nil
        end
      end

      def apply_remove_tags(tag_list, sources, remove_tags, source)
        remove_tags.filter_map do |tag|
          next tag if owner_locked?(sources, tag, source)

          tag_list.delete(tag)
          # remove_tags with source "owner" → tag removed, sources entry KEPT
          # ("owner") — a pinned-absent tag. classified/derived → the tag AND
          # its sources entry are deleted outright (traits-design.md §4).
          source == "owner" ? sources[tag] = "owner" : sources.delete(tag)
          nil
        end
      end

      # ── Single-name helpers ──

      def owner_locked?(sources, name, source)
        source != "owner" && sources[name] == "owner"
      end

      def apply_scale(values, sources, name, value, source)
        if value.nil?
          values.delete(name)
          # Same two behaviors as remove_tags: "owner" keeps a pinned-absent
          # sources entry; classified/derived deletes it outright.
          source == "owner" ? sources[name] = "owner" : sources.delete(name)
        else
          values[name] = value
          sources[name] = source
        end
      end

      def normalize_tags!(values, tag_list)
        normalized = Game::Traits::Vocabulary.tag_names & tag_list
        normalized.empty? ? values.delete("tags") : values["tags"] = normalized
      end

      def persist!(game, values, sources, source)
        new_traits = { "schema_version" => 1, "values" => values, "sources" => sources }
        if source == "classified"
          new_traits["classified_at"] = Time.current.utc.iso8601
        elsif game.traits["classified_at"]
          new_traits["classified_at"] = game.traits["classified_at"]
        end

        game.update!(traits: new_traits)
        GameEmbedIndexJob.perform_later(game.id)
      end

      # ── Validation (raises Pito::Error::TraitInvalid; never partially applies) ──

      def validate!(game:, source:, scales:, add_tags:, remove_tags:)
        errors = source_errors(source)
        errors += name_errors(scales, add_tags, remove_tags)
        errors += source_legality_errors(source, scales, add_tags, remove_tags) if errors.empty?

        raise Pito::Error::TraitInvalid.new(game_id: game.id, errors: errors) if errors.any?
      end

      def source_errors(source)
        return [] if VALID_SOURCES.include?(source)

        [ "unknown source #{source.inspect} (allowed: #{VALID_SOURCES.inspect})" ]
      end

      def name_errors(scales, add_tags, remove_tags)
        errors = scale_name_errors(scales) + tag_name_errors(add_tags, remove_tags)

        overlap = add_tags & remove_tags
        errors << "tag(s) in both add_tags and remove_tags: #{overlap.sort.inspect}" if overlap.any?
        errors
      end

      def scale_name_errors(scales)
        scales.filter_map do |name, value|
          next "unknown scale #{name.inspect}" unless Game::Traits::Vocabulary.scale_names.include?(name)
          next if value.nil? || Game::Traits::Vocabulary.valid_scale_value?(name, value)

          "#{value.inspect} is not a valid value for scale #{name.inspect} " \
            "(allowed: #{Game::Traits::Vocabulary.scales[name]['values'].inspect})"
        end
      end

      def tag_name_errors(add_tags, remove_tags)
        (add_tags + remove_tags).uniq.filter_map do |tag|
          "unknown tag #{tag.inspect}" unless Game::Traits::Vocabulary.tag_names.include?(tag)
        end
      end

      # A source may only touch names whose declared kind legally accepts it
      # (traits-design.md section 1): derived-declared tags accept only
      # "derived"/"owner"; scales and classified-declared tags accept only
      # "classified"/"owner". "owner" is checked upstream (short-circuits
      # this method entirely) because it may touch anything.
      def source_legality_errors(source, scales, add_tags, remove_tags)
        return [] if source == "owner"

        errors = []
        if scales.any? && source == "derived"
          errors << "source \"derived\" cannot touch scale(s): #{scales.keys.sort.inspect}"
        end
        errors + tag_source_legality_errors(source, add_tags, remove_tags)
      end

      def tag_source_legality_errors(source, add_tags, remove_tags)
        derived_tags = Game::Traits::Vocabulary.derived_tag_names

        (add_tags + remove_tags).uniq.filter_map do |tag|
          declared = derived_tags.include?(tag) ? "derived" : "classified"
          next if declared == source

          "source #{source.inspect} not legal for #{declared}-declared tag #{tag.inspect}"
        end
      end
    end
  end
end
