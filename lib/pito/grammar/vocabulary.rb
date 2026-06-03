# frozen_string_literal: true

require "set"

module Pito
  module Grammar
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
