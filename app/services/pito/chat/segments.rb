# frozen_string_literal: true

module Pito
  module Chat
    # Config-driven segment reader for multi-segment verbs.
    #
    # Data lives in config/pito/verbs.yml under each verb's `segments:` block
    # and is loaded/frozen by Pito::Dispatch::Config. This module reads that
    # config and reconstructs Segment value objects with live Ruby constants
    # (builders, fill jobs) and named predicates (emit_if lambdas via
    # Pito::Dispatch::Predicates).
    #
    # Each Segment records one scrollback message a verb emits for an entity:
    #   name         — dash-case identifier (matches verbs.yml key)
    #   builder      — the MessageBuilder class constant
    #   kind         — :system or :enhanced (event chrome)
    #   default      — true when the segment emits with a bare verb (no with/only)
    #   fill         — pending-fill job class constant, or nil
    #   reply_target — Symbol used by the follow-up dispatch table
    #   emit_if      — arity-1 lambda(entity_record) → Boolean, or nil (unconditional)
    class Segments
      Segment = Data.define(:name, :aliases, :builder, :kind, :default, :fill, :reply_target, :emit_if)

      # Returns the ordered, frozen Array of Segments for a verb+entity pair.
      #
      # @param verb   [Symbol]  :show, :analyze (any verb with a segments: block)
      # @param entity [Symbol]  :channel, :vid, or :game
      # @return [Array<Segment>]
      # @raise [ArgumentError] on unknown verb or entity
      def self.for(verb:, entity:)
        verb_config = begin
          Pito::Dispatch::Config.verb(verb)
        rescue KeyError
          raise ArgumentError, "unknown verb: #{verb.inspect}"
        end

        segments_config = verb_config[:segments]
        raise ArgumentError, "unknown verb: #{verb.inspect}" if segments_config.nil?

        entity_config = segments_config[entity]
        raise ArgumentError, "unknown entity: #{entity.inspect} for verb: #{verb.inspect}" if entity_config.nil?

        entity_config.map do |name_key, seg|
          Segment.new(
            name:         name_key.to_s,
            aliases:      Array(seg[:aliases]).map(&:to_s),
            builder:      "Pito::#{seg[:builder]}".constantize,
            kind:         seg[:kind].to_sym,
            default:      seg[:default],
            fill:         seg[:fill]&.constantize,
            reply_target: seg[:reply_target].to_sym,
            emit_if:      Pito::Dispatch::Predicates.get(seg[:emit_if])
          )
        end.freeze
      end

      # @return [Array<String>] ordered dash-case segment names
      def self.names(verb:, entity:)
        self.for(verb:, entity:).map(&:name)
      end

      # @return [Array<String>] names of segments where default: true
      def self.default_names(verb:, entity:)
        self.for(verb:, entity:).select(&:default).map(&:name)
      end

      # Returns a flat Hash mapping every surface token (alias or canonical name)
      # to its canonical segment name, for the given verb+entity.
      # Canonical names are identity-mapped so the parser can use this as a single
      # look-up for both canonical tokens and aliases.
      #
      # @param verb   [Symbol]
      # @param entity [Symbol]
      # @return [Hash<String, String>]   { "similars" => "similar", "similar" => "similar", … }
      def self.alias_map(verb:, entity:)
        self.for(verb:, entity:).each_with_object({}) do |seg, map|
          map[seg.name] = seg.name
          seg.aliases.each { |a| map[a] = seg.name }
        end
      end
    end
  end
end
