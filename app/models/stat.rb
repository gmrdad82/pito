# frozen_string_literal: true

# P4 — Polymorphic stat counter.
#
# Stores per-entity counts that used to live as dedicated columns on
# Channel/Video (`subscriber_count`, `view_count`). One row per
# `(entity, kind)`; `value` is the count and `synced_at` records when it
# was last refreshed from its source.
#
# Reads and writes go through the `Pito::Stats` facade rather than this
# model directly — `Pito::Stats.set` upserts on the
# `(entity_type, entity_id, kind)` unique index.
#
#   kinds:
#     subscribers — Channel subscriber count (YouTube Data API)
#     views       — Channel / Video / Game view count
#     likes       — Video like count (YouTube Data API)
#     comments    — Video comment count (YouTube Data API)
class Stat < ApplicationRecord
  KINDS = %w[subscribers views likes comments].freeze

  belongs_to :entity, polymorphic: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :entity_id,
            uniqueness: { scope: %i[entity_type kind] }
end
