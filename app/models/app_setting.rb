class AppSetting < ApplicationRecord
  encrypts :value, deterministic: true

  # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — `voyage_api_key` lives on the
  # de-facto-singleton AppSetting row so the user can rotate it from the
  # Settings UI without a deploy. NOT deterministic — the key is sensitive,
  # never compared/queried, and benefits from probabilistic encryption.
  encrypts :voyage_api_key

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :value, presence: true

  # Phase 4 §3.5 (Phase B revamp) — when any per-target indexing flag is on,
  # the API key MUST be present. The validation triggers on both directions:
  # flipping a flag true while the key is blank, AND clearing the key while
  # any flag is true. Belt-and-suspenders on top of Notes::EmbedJob's own
  # dual check (model validation prevents the broken state at the form
  # boundary; the job re-checks at HTTP-call time in case of migration drift
  # or direct SQL writes).
  #
  # The validation method name uses the plural ("flags") so future indexing
  # targets (videos, channels, ...) can extend it without renaming.
  validate :voyage_target_flags_require_key

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    record
  end

  # True iff the singleton has a non-blank Voyage API key. Treated as the
  # "Voyage is configured" gate — Notes::EmbedJob short-circuits when this
  # is false even if a per-target flag was somehow flipped true.
  def self.voyage_configured?
    first&.voyage_api_key.present?
  end

  # Per-target flag: project-notes indexing. Returns false (not nil) when no
  # singleton exists so callers can use it directly in conditionals.
  def self.voyage_indexing_project_notes?
    first&.voyage_index_project_notes || false
  end

  private

  def voyage_target_flags_require_key
    return unless voyage_index_project_notes
    return if voyage_api_key.present?

    errors.add(:voyage_api_key,
               "Voyage API key required to enable project-notes indexing.")
  end
end
