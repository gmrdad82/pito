# frozen_string_literal: true

module Pito
  module Dispatch
    # Named predicate registry for a tool's `enabled_if:` gate declared in
    # tools.yml — mirrors Predicates (segment `emit_if:` guards), but arity-0:
    # a tool's availability is GLOBAL (provider/model/key configured), never
    # per-entity.
    #
    # Each predicate is a lambda() → Boolean, keyed by the snake_case name a
    # tool's `enabled_if:` names. NEVER raises — a readiness probe that could
    # raise would take a presentation pass down with it; every registered
    # predicate wraps a non-raising check (Ai::Client.configured? for
    # "ai_configured", never Ai::Client.current).
    #
    # Consumed by Pito::Dispatch::Matrix (#tool_enabled? / #available?),
    # which resolves it LIVE on every call — never memoized — so a
    # mid-conversation `/config ai` changes what's offered on the very next
    # read, with no Matrix.reload! required.
    module Availability
      REGISTRY = {
        "ai_configured" => -> { ::Ai::Client.configured? }
      }.freeze

      module_function

      # Frozen list of registered condition names — the schema validator's
      # allowed set for `enabled_if:`.
      def names
        REGISTRY.keys.freeze
      end

      # True when +name+'s condition currently holds. Blank/unregistered
      # fails OPEN to "ready": schema validation already guarantees every
      # declared `enabled_if:` names a registered condition, so this is a
      # defensive default, never a gate a real config value can trip.
      def ready?(name)
        return true if name.blank?

        fn = REGISTRY[name.to_s]
        fn.nil? || fn.call
      end
    end
  end
end
