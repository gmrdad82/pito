# frozen_string_literal: true

module Pito
  module Dispatch
    # Named predicate registry for segment emit_if guards declared in verbs.yml.
    #
    # Each predicate is an arity-1 lambda(entity) → Boolean, keyed by the
    # snake_case name used in a segment's `emit_if:` field. Schema::PREDICATES
    # is derived from `.names` so the schema validator rejects any unknown name.
    #
    # Mirrors the Resolvers registry pattern.
    module Predicates
      REGISTRY = {
        "has_any_videos"    => ->(entity) { entity.videos.any? },
        "has_linked_game"   => ->(entity) { entity.linked_games.first.present? },
        "has_linked_games"  => ->(entity) { entity.linked_games.any? },
        "has_linked_videos" => ->(entity) { entity.linked_videos.any? }
      }.freeze

      module_function

      # Frozen list of registered predicate names.
      def names
        REGISTRY.keys.freeze
      end

      # Returns the lambda for +name+, or nil when name is absent or nil.
      def get(name)
        REGISTRY[name.to_s] if name
      end
    end
  end
end
