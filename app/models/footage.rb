# frozen_string_literal: true

class Footage < ApplicationRecord
  # ── Constants ─────────────────────────────────────────────────
  ORIENTATIONS = {
    landscape: "landscape",
    portrait:  "portrait",
    square:    "square"
  }.freeze

  # ── Associations ──────────────────────────────────────────────
  belongs_to :game  # required — game_id is NOT NULL in the schema

  # ── Validations ───────────────────────────────────────────────
  validates :filename, presence: true,
                       uniqueness: { scope: :game_id, case_sensitive: true }
  validates :orientation, inclusion: { in: ORIENTATIONS.values }, allow_nil: true

  # ── Derived attributes ────────────────────────────────────────
  def audio_track_count
    audio_track_names.length
  end
end
