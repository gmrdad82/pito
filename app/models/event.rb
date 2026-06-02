# frozen_string_literal: true

class Event < ApplicationRecord
  KINDS = %w[
    echo assistant_text error confirmation_prompt thinking
    user_message thought tool_output status_footer
  ].freeze

  belongs_to :conversation
  belongs_to :turn

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :position, presence: true

  def self.next_position_for(conversation)
    where(conversation_id: conversation.id).maximum(:position).to_i + 1
  end

  # Atomic create: retries on position collision so concurrent jobs don't
  # surface PG::UniqueViolation to the user. Up to 5 attempts before re-raising.
  def self.create_with_position!(conversation:, **attrs)
    attempts = 0
    begin
      create!(conversation:, position: next_position_for(conversation), **attrs)
    rescue ActiveRecord::RecordNotUnique
      raise if (attempts += 1) >= 5
      retry
    end
  end
end
