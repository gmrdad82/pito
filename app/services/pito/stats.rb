# frozen_string_literal: true

module Pito
  # Stats facade — the single seam for reading and writing per-entity
  # counters (subscribers / views) stored in the polymorphic `stats`
  # table (P4).
  #
  # == Contract
  #
  #   Pito::Stats.get(entity, kind)        → Integer | nil
  #   Pito::Stats.set(entity, kind, value) → Stat
  #   Pito::Stats.for(entity)              → Hash{Symbol => Integer}
  #
  # `kind` accepts a Symbol or String drawn from `Stat::KINDS`
  # (`:subscribers`, `:views`). An unknown kind raises ArgumentError.
  #
  # `get` returns the stored `value` (or nil when no row exists — callers
  # that previously read a nullable column keep the same nil semantics).
  #
  # `set` upserts on the `(entity_type, entity_id, kind)` unique index and
  # stamps `synced_at` to the moment of the write. A nil value is stored
  # as-is (distinguishes "not available" from zero), matching the dropped
  # columns' nullability.
  #
  # `for` returns the entity's known counters keyed by kind symbol — only
  # kinds that have a row are present.
  module Stats
    module_function

    # @param entity [ActiveRecord::Base]
    # @param kind   [Symbol, String]
    # @return [Integer, nil]
    def get(entity, kind)
      kind = normalize_kind(kind)
      entity.stats.find_by(kind: kind)&.value
    end

    # Upsert the counter for *entity*/*kind* and stamp `synced_at`.
    #
    # @param entity [ActiveRecord::Base]
    # @param kind   [Symbol, String]
    # @param value  [Integer, nil]
    # @return [Stat] the persisted row
    def set(entity, kind, value)
      kind = normalize_kind(kind)
      now  = Time.current

      Stat.upsert(
        {
          entity_type: entity.class.polymorphic_name,
          entity_id:   entity.id,
          kind:        kind,
          value:       value,
          synced_at:   now,
          created_at:  now,
          updated_at:  now
        },
        unique_by: %i[entity_type entity_id kind]
      )

      entity.stats.reset
      entity.stats.find_by(kind: kind)
    end

    # @param entity [ActiveRecord::Base]
    # @return [Hash{Symbol => Integer}] present counters keyed by kind
    def for(entity)
      entity.stats.each_with_object({}) do |stat, acc|
        acc[stat.kind.to_sym] = stat.value
      end
    end

    def normalize_kind(kind)
      kind = kind.to_s
      unless Stat::KINDS.include?(kind)
        raise ArgumentError, "unknown stat kind: #{kind.inspect} (expected one of #{Stat::KINDS.inspect})"
      end

      kind
    end
  end
end
