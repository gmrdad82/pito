# frozen_string_literal: true

module Pito
  module Grammar
    Slot = Data.define(:name, :kind, :source, :optional, :repeatable, :synonyms, :introducer, :condition) do
      def initialize(name:, kind:, source: nil, optional: false, repeatable: false, synonyms: [], introducer: nil, condition: nil)
        super
      end

      # name        — Symbol, slot identifier (e.g. :genre, :code, :provider)
      # kind        — Symbol, one of :literal, :enum, :kv, :free, :connective
      # source      — Array of literals, a Symbol naming a vocabulary (e.g. :genres), or :dynamic
      #               (resolved at runtime). May be nil for :free slots.
      # optional    — Boolean, whether the slot may be absent
      # repeatable  — Boolean, whether the slot may capture multiple values
      #               (joined by an `and` connective downstream)
      # synonyms    — Array of extra surface forms for a :literal slot (defaults to [])
      # introducer  — Symbol or nil; a connective word that must precede this slot's value
      #               (e.g. :for in "... for playstation")
      # condition   — Hash or nil; e.g. { provider: %w[sound fx] } means this slot is
      #               eligible only when the already-resolved value for slot :provider
      #               is one of the given strings (compared case-insensitively).

      def optional?
        optional
      end

      def repeatable?
        repeatable
      end

      # Returns true when the slot is eligible given the already-resolved values.
      # @param resolved_values [Hash] e.g. { provider: "sound" }
      def eligible?(resolved_values = {})
        return true if condition.nil?

        condition.all? do |slot_name, allowed|
          resolved = resolved_values[slot_name.to_sym].to_s.downcase
          allowed.any? { |v| v.to_s.downcase == resolved }
        end
      end
    end
  end
end
