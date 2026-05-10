# Phase 4 §3.4 — Footage holds probed metadata pushed by the `pito footage`
# importer (Phase B). All ffprobe-derived fields are nullable so a row can
# land minimally then get hydrated as the importer fills in details.
#
# Phase 8 — tenant drop. The `tenant_id` column and
# `denormalize_tenant_from_project` callback are gone; `local_path`
# uniqueness is install-wide.
class Footage < ApplicationRecord
  belongs_to :project, counter_cache: true
  belongs_to :game, optional: true

  enum :kind, { a_roll: 0, b_roll: 1 }, validate: true
  enum :source, { obs: 0, camera: 1 }, validate: true
  enum :orientation, { landscape: 0, portrait: 1 }

  validates :local_path, presence: true, uniqueness: true
  validates :filename, presence: true
  validates :bit_depth, inclusion: { in: [ 8, 10, 12 ] }
  validates :platform, presence: true, if: :game_id?
  validate :platform_must_match_game_allowlist
  validate :commentary_track_consistency

  # Phase 4 Wave 3.5+ — `/projects` index aggregates. Keep the parent
  # project's `footage_duration_seconds` cache in sync whenever a footage's
  # duration changes, the row moves to a different project, or the row is
  # destroyed. Counter-cache columns (`footages_count`) handle row-count;
  # this callback handles the SUM-of-duration display.
  #
  # When `project_id` changes the OLD project also needs a refresh — its
  # cached sum still includes the moved row's duration. The dedicated
  # `refresh_previous_project_footage_duration` callback handles that
  # case (and only fires when `project_id` actually changed).
  after_save :recompute_project_footage_duration,
             if: :saved_change_relevant_to_footage_duration?
  after_save :refresh_previous_project_footage_duration,
             if: :saved_change_to_project_id?
  after_destroy :recompute_project_footage_duration

  private

  # Re-sums the parent project's footage durations and writes the cached
  # total via `update_columns` (skips validations / callbacks). Guarded
  # against the case where the project has already been destroyed in the
  # same transaction (`Project#destroy` cascades to dependent footages
  # via `dependent: :destroy`; by the time the footage's after_destroy
  # fires, the parent project row may be gone). `find_by` (not `find`)
  # silently returns nil on a missing project, mirroring the no-op
  # pattern Rails uses for orphaned counter-cache writes.
  def recompute_project_footage_duration
    return unless project_id
    project = Project.find_by(id: project_id)
    return unless project
    project.update_columns(
      footage_duration_seconds: project.footages.sum(:duration_seconds).to_i
    )
  end

  # `saved_change_to_*?` only returns true on save (not destroy). The
  # destroy path is wired separately via `after_destroy`. Recompute
  # whenever the duration changed OR the row moved between projects
  # (the previous project also needs a refresh — handled below).
  def saved_change_relevant_to_footage_duration?
    saved_change_to_duration_seconds? || saved_change_to_project_id?
  end

  # When a footage moves between projects, the OLD project's cache still
  # includes this row's duration. Recompute it from `saved_changes`.
  def refresh_previous_project_footage_duration
    previous_project_id = saved_change_to_project_id&.first
    return unless previous_project_id
    previous = Project.find_by(id: previous_project_id)
    return unless previous
    previous.update_columns(
      footage_duration_seconds: previous.footages.sum(:duration_seconds).to_i
    )
  end

  def platform_must_match_game_allowlist
    return if game.blank? || platform.blank?

    allowed = Array(game.platforms).filter_map do |entry|
      next unless entry.is_a?(Hash)
      entry["platform"] || entry[:platform]
    end

    unless allowed.include?(platform)
      errors.add(:platform, "must be one of the game's platforms (#{allowed.join(', ')})")
    end
  end

  def commentary_track_consistency
    # Spec §3.4: has_commentary_track defaults false; importer flips it true
    # when audio_track_count >= 2. We don't force-derive here (the column is
    # writable from the API), but we reject obviously inconsistent claims.
    return if audio_track_count.nil?
    if has_commentary_track && audio_track_count < 2
      errors.add(:has_commentary_track, "requires audio_track_count >= 2")
    end
  end
end
