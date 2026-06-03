# frozen_string_literal: true

module Pito
  module Grammar
    Slot = Data.define(:name, :kind, :source, :optional, :repeatable, :synonyms, :introducer) do
      def initialize(name:, kind:, source: nil, optional: false, repeatable: false, synonyms: [], introducer: nil)
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

      def optional?
        optional
      end

      def repeatable?
        repeatable
      end
    end
  end
end
