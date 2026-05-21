# Phase 4 §3.4 — Footage holds probed metadata pushed by the `pito footage`
# importer (Phase B). All ffprobe-derived fields are nullable so a row can
# land minimally then get hydrated as the importer fills in details.
#
# Phase 8 — tenant drop. The `tenant_id` column and
# `denormalize_tenant_from_project` callback are gone; `local_path`
# uniqueness is install-wide.
#
# D18 (2026-05-21) — Projects dropped. Footage now attaches directly to
# Game; the `project_id` column + `belongs_to :project` + project-side
# cache callbacks are gone.
class Footage < ApplicationRecord
  # Phase 20 — friendly URLs. Slug derives from the `local_path`
  # basename (without extension), parameterized for URL safety. Two
  # footages can share a basename (`/a/clip.mp4` vs `/b/clip.mp4`); on
  # collision we append `-<id>` to disambiguate. There is no `slug`
  # column — `to_param` returns the derived slug at request time and
  # the custom `Footage.friendly` finder reverses the derivation when
  # resolving URL parameters.
  belongs_to :game, optional: true

  # Rails 8.1 — defensive: lock the enum-backing column types.
  attribute :kind, :integer
  attribute :source, :integer
  attribute :orientation, :integer
  enum :kind, { a_roll: 0, b_roll: 1 }, validate: true
  enum :source, { obs: 0, camera: 1 }, validate: true
  enum :orientation, { landscape: 0, portrait: 1 }

  validates :local_path, presence: true, uniqueness: true
  validates :filename, presence: true

  # Phase 20 — friendly URLs.
  #
  # Returns the basename of `local_path` (sans extension), parameterized
  # via `Pito::SlugBuilder`. When another Footage's basename collapses
  # to the same slug, append `-<id>` to disambiguate. Falls back to
  # `footage-<id>` when `local_path` is unexpectedly blank.
  def url_slug
    base = bare_basename
    return "footage-#{id}" if base.blank?
    return base unless basename_collides?(base)

    "#{base}-#{id}"
  end

  # Override so route helpers emit the slug.
  def to_param
    url_slug
  end

  # Phase 20 — friendly URLs. Reverse the `to_param` derivation so a
  # routed slug (or integer id) resolves to a single record. Mirrors the
  # `Model.friendly.find` shape used everywhere else in the app so
  # controllers can stay uniform.
  def self.friendly
    FriendlyFinder.new(self)
  end

  # Custom finder for Footage. The slug column doesn't exist; lookup
  # walks `local_path` after parameterizing the basename. Integer-id
  # lookups still resolve normally for backwards compatibility.
  class FriendlyFinder
    def initialize(scope)
      @scope = scope
    end

    def find(input)
      str = input.to_s
      raise ActiveRecord::RecordNotFound, "Footage param can't be blank" if str.blank?

      # Backwards compat — integer-id lookup wins when the input is a
      # bare integer.
      if str.match?(/\A\d+\z/)
        record = @scope.find_by(id: str.to_i)
        return record if record
      end

      # Slug-with-trailing-id form: `<base>-<id>` where the basename
      # collided in `to_param`. Resolve by id first, then verify the
      # leading basename matches so we don't accidentally hit a row
      # whose own basename happens to end with `-<digits>`.
      m = str.match(/\A(.+)-(\d+)\z/)
      if m
        candidate = @scope.find_by(id: m[2].to_i)
        return candidate if candidate && candidate.send(:bare_basename) == m[1]
      end

      # Plain basename slug: pick the single matching row (first by id
      # — uniqueness across local_path prevents true duplicates of the
      # full path; basename collisions are resolved via the trailing-id
      # form above).
      record = @scope.where("local_path LIKE ?", "%/#{str}.%").or(
        @scope.where("local_path LIKE ?", "%/#{str}")
      ).order(:id).first
      record ||= match_by_parameterized_basename(str)
      return record if record

      raise ActiveRecord::RecordNotFound,
            "Couldn't find Footage with slug or id=#{input.inspect}"
    end

    private

    # Fallback: walk every row and re-parameterize the basename. Cheap
    # in a single-tenant install (Footage table is small); avoids
    # mismatches when the basename has unicode / spaces / case
    # differences that LIKE wouldn't pick up.
    def match_by_parameterized_basename(slug)
      @scope.find_each do |row|
        return row if row.send(:bare_basename) == slug
      end
      nil
    end
  end
  validates :bit_depth, inclusion: { in: [ 8, 10, 12 ] }
  validates :platform, presence: true, if: :game_id?
  validate :platform_must_match_game_allowlist
  validate :commentary_track_consistency

  private

  # Phase 20 — friendly URLs. Bare basename (no extension), parameterized.
  def bare_basename
    return "" if local_path.blank?

    name = File.basename(local_path.to_s, File.extname(local_path.to_s))
    Pito::SlugBuilder.build(name, limit: 80)
  end

  # Returns true when another Footage's basename (sans extension) would
  # produce the same parameterized slug.
  def basename_collides?(base)
    self.class.where.not(id: id).find_each do |other|
      next if other.local_path.blank?

      other_base = File.basename(other.local_path.to_s, File.extname(other.local_path.to_s))
      return true if Pito::SlugBuilder.build(other_base, limit: 80) == base
    end
    false
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
