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

  # Returns conversations ordered by last activity (most recent first).
  # "Last activity" = MAX(events.created_at) for the conversation, falling
  # back to the conversation's own created_at when it has no events.
  # Each returned record has a `last_activity_at` virtual attribute.
  def self.by_recent_activity
    left_joins(:events)
      .select(
        "conversations.*",
        "COALESCE(MAX(events.created_at), conversations.created_at) AS last_activity_at"
      )
      .group("conversations.id")
      .order("last_activity_at DESC")
  end

  # Returns a hash with two keys:
  #   :recent — conversations whose last_activity_at is within 24 h of the
  #              most-recent conversation's last_activity_at (i.e. relative to
  #              the newest, NOT relative to now).
  #   :older  — the rest, ordered most-recent first.
  #
  # Edge cases:
  #   - Empty collection → both buckets are [].
  #   - Single conversation → it lands in :recent; :older is [].
  #   - All within 24 h → all land in :recent; :older is [].
  def self.recency_groups
    all_ordered = by_recent_activity.to_a
    return { recent: [], older: [] } if all_ordered.empty?

    cutoff = all_ordered.first.last_activity_at - 24.hours
    recent, older = all_ordered.partition { |c| c.last_activity_at > cutoff }
    { recent: recent, older: older }
  end

  private

  def set_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
