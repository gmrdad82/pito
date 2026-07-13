# frozen_string_literal: true

class Event < ApplicationRecord
  KINDS = %w[
    echo system error enhanced thinking confirmation
    system_follow_up enhanced_follow_up confirmation_follow_up
    theme_diff ai
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
  #
  # Also THE living-background stamp point (2.1.0 F3, Option B): this is the
  # one method every event-creating door goes through (Finalizer, jobs,
  # controller fast-paths, Broadcaster), so eligible kinds pick up their
  # `fx` context {context, covers} here — web, JSON mirror, and backfill all
  # speak the same mood. Never raises: a failed derivation just means the
  # sky answers.
  def self.create_with_position!(conversation:, **attrs)
    stamp_fx!(attrs)
    attempts = 0
    begin
      create!(conversation:, position: next_position_for(conversation), **attrs)
    rescue ActiveRecord::RecordNotUnique
      raise if (attempts += 1) >= 5
      retry
    end
  end

  def self.stamp_fx!(attrs)
    kind    = attrs[:kind]
    payload = attrs[:payload]
    return unless kind && payload.is_a?(Hash) && !payload.frozen?
    return unless Pito::Fx::Context.eligible?(kind)

    # Builders hand symbol-keyed payloads at create time; jsonb stringifies
    # on save. Derive from a string-keyed view so both shapes stamp alike.
    fx = Pito::Fx::Context.derive(kind:, payload: payload.transform_keys(&:to_s))
    payload["fx"] = fx if fx
  rescue StandardError => e
    Rails.logger.warn("[Fx] stamp failed: #{e.class}: #{e.message}")
  end
end
