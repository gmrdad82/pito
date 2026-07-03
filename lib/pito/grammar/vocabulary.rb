# frozen_string_literal: true

require "set"

module Pito
  module Grammar
    # Immutable value object representing a named set of allowed vocabulary members.
    # Used by the normalizer and autocomplete engine to validate and canonicalize
    # token values.
    #
    # CONSTRUCTION
    #   Vocabulary.define(name:, canonical: [], synonyms: {}, fillers: [],
    #                     dynamic: false, resolver: nil) -> Vocabulary
    #   All attributes are frozen on construction.  Do not subclass; use .define.
    #
    # RESOLUTION ORDER  (Vocabulary#resolve(raw) -> String | nil)
    #   1. Canonical match — case-insensitive comparison against the canonical array.
    #      Returns the canonical form (preserving its original casing).
    #   2. Synonym match   — looks up raw.downcase in the synonyms hash.
    #      Returns the canonical form the synonym maps to.
    #   3. Dynamic resolver — for dynamic: true vocabs, calls resolver.call(nil)
    #      to obtain the member list, then applies step-1 logic on those results.
    #   4. nil              — token is not a member of this vocabulary.
    #
    # MEMBERS
    #   members(context:) — for static vocabs, returns the canonical array.
    #     For dynamic vocabs, calls resolver.call(context); context is passed
    #     through unchanged (e.g. the current user or conversation record).
    #
    # FILLER WORDS
    #   filler?(raw) — returns true when raw.downcase is in the fillers set.
    #   Filler words are silently dropped by the normalizer during slot walking.
    #   They are stored in a frozen Set (O(1) lookup).
    #
    # SERIALIZATION
    #   to_h — produces a Hash suitable for JSON serialization into the frontend
    #     catalog.  Dynamic vocabs omit the canonical array (resolver output is
    #     not static and must be fetched at runtime).
    class Vocabulary
      attr_reader :name, :canonical, :synonyms, :fillers, :resolver

      def self.define(name:, canonical: [], synonyms: {}, fillers: [], dynamic: false, resolver: nil)
        new(name:, canonical:, synonyms:, fillers:, dynamic:, resolver:)
      end

      def initialize(name:, canonical: [], synonyms: {}, fillers: [], dynamic: false, resolver: nil)
        @name      = name.to_sym
        @canonical = canonical.freeze
        @synonyms  = synonyms.transform_keys(&:downcase).freeze
        @fillers   = Set.new(fillers.map(&:downcase)).freeze
        @dynamic   = dynamic
        @resolver  = resolver
      end

      def dynamic?
        @dynamic
      end

      # Value equality — two Vocabularies are equal when they carry the same name,
      # canonical list, synonyms, fillers, dynamic flag, and resolver identity.
      # This allows ConfigSource (which builds fresh instances on each call) to produce
      # Vocabulary objects that compare equal to identically-configured ones in tests
      # and assertions without requiring the caller to hold a reference to the exact instance.
      def ==(other)
        return false unless other.is_a?(Vocabulary)

        name == other.name &&
          canonical == other.canonical &&
          synonyms == other.synonyms &&
          fillers == other.fillers &&
          dynamic? == other.dynamic? &&
          resolver.equal?(other.resolver)
      end

      alias eql? ==

      def hash
        [ name, canonical, synonyms, fillers.to_a.sort, dynamic?, resolver.object_id ].hash
      end

      # Resolves a raw token to its canonical form, or nil if not found.
      def resolve(raw)
        return nil if raw.nil? || raw.to_s.strip.empty?

        downcased = raw.to_s.downcase

        # Check canonical members case-insensitively
        match = canonical.find { |c| c.downcase == downcased }
        return match if match

        # Check synonym keys
        return synonyms[downcased] if synonyms.key?(downcased)

        # For dynamic vocabs, call the resolver and check its output
        if dynamic?
          dynamic_members = members(context: nil)
          match = dynamic_members.find { |m| m.downcase == downcased }
          return match if match
        end

        nil
      end

      # Fuzzy fallback: resolves a raw token to its canonical form using
      # Levenshtein distance when exact + synonym resolution misses.
      # Returns nil for dynamic vocabs, ambiguous matches (0 or ≥2 canonicals
      # within threshold), and tokens that are an exact match (those are handled
      # by #resolve).
      #
      # Distance threshold: token.length <= 4 → 1, else → 2.
      # Checks canonical forms + synonym keys (case-insensitive), dist > 0 only
      # (exact matches belong to #resolve).
      def resolve_fuzzy(token)
        return nil if token.nil? || token.to_s.strip.empty?
        return nil if dynamic?  # handles/titles — never fuzzy

        downcased = token.to_s.downcase
        threshold = downcased.length <= 4 ? 1 : 2
        hits      = Set.new

        canonical.each do |c|
          dist = Pito::Fuzzy.levenshtein(downcased, c.downcase)
          hits.add(c) if dist > 0 && dist <= threshold
        end

        synonyms.each do |syn_key, canon|
          dist = Pito::Fuzzy.levenshtein(downcased, syn_key)
          hits.add(canon) if dist > 0 && dist <= threshold
        end

        hits.size == 1 ? hits.first : nil
      end

      # Returns true when raw (downcased) is a filler word.
      def filler?(raw)
        fillers.include?(raw.to_s.downcase)
      end

      # Returns the full member list. For static vocabs, this is canonical.
      # For dynamic vocabs, calls the resolver with the given context.
      def members(context:)
        return canonical unless dynamic?
        return [] if resolver.nil?

        resolver.call(context)
      end

      # Serializable form for the JSON catalog.
      # Dynamic vocabs omit member data entirely.
      def to_h
        h = {
          name:     name,
          synonyms: synonyms,
          fillers:  fillers.to_a,
          dynamic:  dynamic?
        }
        h[:canonical] = canonical unless dynamic?
        h
      end
    end
  end
end
