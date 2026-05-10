# Phase 14 §3 — `VideoGameLink`. Polymorphic-ish join row tying a Video
# to either a Game or a Bundle (per row, exactly one target).
#
# - `link_type` enum (`game: 0`, `bundle: 1`).
# - Either `game_id` (when `link_type = game`) or `bundle_id` (when
#   `link_type = bundle`) is set; the other is NULL. Enforced both at
#   the DB layer (CHECK constraint) and at the model layer
#   (`exactly_one_target` validator).
# - `is_primary` is a hint for analytics weighting (Phase 13). Multiple
#   primaries per Video are allowed (master-agent decision #2).
# - `created_by_user_id` audit column populated from `Current.user`
#   on create (master-agent decision #4).
# - `after_*_commit :recompute_game_footage_cache` keeps
#   `Game#hours_of_footage_cached` in sync with the linked Video durations.
class VideoGameLink < ApplicationRecord
  enum :link_type, { game: 0, bundle: 1 }, prefix: :link

  belongs_to :video
  belongs_to :game, optional: true
  belongs_to :bundle, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  validate :exactly_one_target
  validates :game_id, uniqueness: { scope: :video_id, allow_nil: true }
  validates :bundle_id, uniqueness: { scope: :video_id, allow_nil: true }

  before_validation :stamp_created_by_user, on: :create

  # Recompute the game-side footage cache on link create AND link
  # destroy. A single `after_commit` (rather than two `after_*_commit`
  # declarations of the same method) — registering the same method
  # name twice merges into ONE callback with the union of `:if`
  # filters, producing an impossible "create AND destroy in the same
  # transaction" gate.
  after_commit :recompute_game_footage_cache, on: %i[create destroy]

  # The linked target (the Game or the Bundle), useful in views.
  def target
    link_game? ? game : bundle
  end

  private

  def exactly_one_target
    if link_game? && (game_id.blank? || bundle_id.present?)
      errors.add(:base, "game link must have game_id and no bundle_id")
    end
    if link_bundle? && (bundle_id.blank? || game_id.present?)
      errors.add(:base, "bundle link must have bundle_id and no game_id")
    end
  end

  def stamp_created_by_user
    return if created_by_user_id.present?
    self.created_by_user_id = Current.user&.id
  end

  # Game-side cache. Sums `Game#videos`'s `duration_seconds` after
  # commit (the linked-video set is up-to-date by then). Rounded to
  # the nearest hour. Bundles do not carry a `hours_of_footage_cached`
  # column today — Phase 13 derives bundle aggregates on the fly.
  def recompute_game_footage_cache
    return unless link_game?

    # On destroy, `game` association may already be cleared (Rails
    # nullifies the in-memory pointer when the parent is destroyed via
    # CASCADE). `game_id` survives in the in-memory attributes, so we
    # fall through to a `find_by` lookup. If the game itself was
    # deleted (CASCADE from the games table), there is no cache to
    # recompute — return.
    target_game = game || Game.find_by(id: game_id)
    return unless target_game
    return if target_game.destroyed?

    total = target_game.videos.sum(:duration_seconds).to_i
    target_game.update_column(:hours_of_footage_cached, (total / 3600.0).round)
  end
end
