# Phase 14 §2 — BundleMember join.
#
# Joins a Bundle to a Game with a `position` integer for ordering.
# Default position on create is `MAX(position) + 1`. Composite
# uniqueness on (bundle_id, game_id). Cascade on delete from either
# side; the bundle's cover is invalidated and re-enqueued via
# `BundleCoverBuild` after_create / after_destroy.
class BundleMember < ApplicationRecord
  belongs_to :bundle
  belongs_to :game

  validates :game_id, uniqueness: { scope: :bundle_id }
  validates :position, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 0
  }

  before_validation :assign_position, on: :create

  # A single `after_commit` (rather than two `after_*_commit` calls of
  # the same method name) — Rails registers two same-named callbacks
  # as ONE entry with a UNION of `:if` filters, producing an
  # impossible "create AND destroy in the same transaction" gate.
  after_commit :enqueue_cover_rebuild, on: %i[create destroy]

  # Phase 34 (2026-05-18) — re-embed the parent Bundle when its
  # membership changes. The aggregated summary (and the `game_count`
  # facet on the Meilisearch document) both depend on the join set,
  # so add / remove triggers a re-index. Same `:create destroy` gate
  # as the cover-rebuild hook — `update` on the join row (a position
  # tweak) does not change the searchable text.
  after_commit :enqueue_bundle_voyage_index, on: %i[create destroy]

  private

  def assign_position
    return if position.present? && position != 0
    max = bundle&.bundle_members&.maximum(:position)
    self.position = (max.nil? ? 0 : max + 1)
  end

  def enqueue_cover_rebuild
    BundleCoverBuild.perform_async(bundle_id) if bundle_id.present?
  end

  def enqueue_bundle_voyage_index
    BundleVoyageIndexJob.perform_later(bundle_id) if bundle_id.present?
  end
end
