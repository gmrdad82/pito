# frozen_string_literal: true

class Turn < ApplicationRecord
  belongs_to :conversation
  has_many :events, -> { order(:position) }, dependent: :destroy

  before_create :stamp_started_at

  validates :input_kind, inclusion: { in: %w[slash chat] }
  validates :position, presence: true
  validates :input_text, presence: true

  # ── Timing ───────────────────────────────────────────────────
  def elapsed_seconds
    return nil if started_at.nil?

    finish = completed_at || Time.current
    (finish - started_at).round(1)
  end

  # ── Query helpers ────────────────────────────────────────────
  def self.next_position_for(conversation)
    where(conversation_id: conversation.id).maximum(:position).to_i + 1
  end

  # Returns the most recent Turn in the conversation, or nil if none exist.
  def self.last_for(conversation)
    where(conversation_id: conversation.id).order(:position).last
  end

  private

  def stamp_started_at
    self.started_at ||= Time.current
  end
end
