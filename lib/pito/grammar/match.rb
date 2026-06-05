# frozen_string_literal: true

module Pito
  module Grammar
    Match = Data.define(:namespace, :name, :values, :kwargs, :leftovers, :unknowns, :confidence, :matched) do
      def initialize(namespace:, name: nil, values: {}, kwargs: {}, leftovers: [], unknowns: [], confidence: 0.0, matched: false)
        super
      end

      # namespace   — Symbol, one of :slash, :chat, :hashtag
      # name        — Symbol, resolved canonical command name, or nil if nothing matched
      # values      — Hash slot_name(Symbol) => resolved canonical value (String) or Array<String>
      #               for a repeatable slot
      # kwargs      — Hash slot_name(Symbol) => value, for :kv slots
      # leftovers   — Array<String> raw words not consumed by any slot
      # unknowns    — Array<String> words that targeted an enum slot but failed to resolve
      # matched     — Boolean, whether a spec matched at all
      # confidence  — Float 0.0..1.0

      def matched?
        matched
      end
    end
  end
end
