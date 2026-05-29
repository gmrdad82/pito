# frozen_string_literal: true

class Turn < ApplicationRecord
  belongs_to :conversation
  has_many :events, -> { order(:position) }, dependent: :destroy

  validates :input_kind, inclusion: { in: %w[slash chat] }
  validates :position, presence: true
  validates :input_text, presence: true

  def self.next_position_for(conversation)
    where(conversation_id: conversation.id).maximum(:position).to_i + 1
  end

  # Returns the most recent Turn in the conversation, or nil if none exist.
  def self.last_for(conversation)
    where(conversation_id: conversation.id).order(:position).last
  end
end
