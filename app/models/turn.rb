# frozen_string_literal: true

class Turn < ApplicationRecord
  belongs_to :conversation
  has_many :events, -> { order(:position) }, dependent: :destroy

  before_create :stamp_started_at

  # String-backed enum — DB stores "slash"/"chat"/"hashtag", Ruby exposes turn.slash? / turn.chat? / turn.hashtag?
  enum :input_kind, { slash: "slash", chat: "chat", hashtag: "hashtag" }, validate: true

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

  # The raw input as safe to surface in the up/down recall history — `/config`
  # credentials and `/login` codes masked (see Pito::InputMasking).
  def display_text
    Pito::InputMasking.for_history(input_text)
  end

  private

  def stamp_started_at
    self.started_at ||= Time.current
  end
end
