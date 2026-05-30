# frozen_string_literal: true

class Conversation < ApplicationRecord
  has_many :turns, -> { order(:position) }, dependent: :destroy
  has_many :events, -> { order(:position) }, dependent: :destroy

  before_create :set_uuid

  normalizes :uuid, with: ->(value) { value&.downcase }

  validates :uuid, uniqueness: { case_sensitive: true }

  # ── Routing ─────────────────────────────────────────────────
  # Use the UUID in URLs instead of the numeric primary key.
  def to_param
    uuid
  end

  # ── Display ─────────────────────────────────────────────────
  def display_name
    title.presence || "Unnamed #{id}"
  end

  # ── Query helpers ────────────────────────────────────────────
  def self.singleton
    first_or_create!
  end

  private

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
