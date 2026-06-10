# frozen_string_literal: true

class Footage < ApplicationRecord
  # ── Associations ──────────────────────────────────────────────
  belongs_to :game  # required — game_id is NOT NULL in the schema

  # ── Validations ───────────────────────────────────────────────
  # filename is unique per game — the skip-if-already-imported key.
  validates :filename, presence: true,
                       uniqueness: { scope: :game_id, case_sensitive: true }
end
