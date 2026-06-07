# frozen_string_literal: true

class Event < ApplicationRecord
  KINDS = %w[
    echo system error enhanced thinking confirmation
    system_follow_up enhanced_follow_up confirmation_follow_up
    theme_diff
  ].freeze

  belongs_to :conversation
  belongs_to :turn

  # Normalize symbol → string so construction sites can use :kind symbols
  # (e.g. kind: :system) while the DB column stores strings.
  normalizes :kind, with: ->(k) { k.to_s }

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
