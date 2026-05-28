# frozen_string_literal: true

class Event < ApplicationRecord
  KINDS = %w[
    echo assistant_text error confirmation_prompt
    user_message thought tool_output status_footer
  ].freeze

  belongs_to :conversation
  belongs_to :turn

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :position, presence: true

  def self.next_position_for(conversation)
    where(conversation_id: conversation.id).maximum(:position).to_i + 1
  end
end
