# Phase 4 §3.4 — Footage holds probed metadata pushed by the `pito footage`
# importer (Phase B). All ffprobe-derived fields are nullable so a row can
# land minimally then get hydrated as the importer fills in details.
class Footage < ApplicationRecord
  belongs_to :project, counter_cache: true
  belongs_to :game, optional: true
  belongs_to :tenant, optional: true

  enum :kind, { a_roll: 0, b_roll: 1 }, validate: true
  enum :source, { obs: 0, camera: 1 }, validate: true
  enum :orientation, { landscape: 0, portrait: 1 }

  validates :local_path, presence: true,
                         uniqueness: { scope: :tenant_id }
  validates :filename, presence: true
  validates :bit_depth, inclusion: { in: [ 8, 10, 12 ] }
  validates :platform, presence: true, if: :game_id?
  validate :platform_must_match_game_allowlist
  validate :commentary_track_consistency

  before_validation :denormalize_tenant_from_project

  private

  def denormalize_tenant_from_project
    self.tenant_id ||= project&.tenant_id
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
