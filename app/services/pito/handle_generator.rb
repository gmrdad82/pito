# frozen_string_literal: true

module Pito
  # Generates a short, human-readable handle like "alpha-1322" for use in
  # follow-up-able events.
  #
  # Uniqueness is checked across ALL events that carry a `reply_handle`
  # payload field (including consumed ones — consumed handles are still
  # reserved so the generator never re-picks them).
  #
  # Format: "<greek-word>-<4-digit-number>" e.g. "delta-4823".
  # Fallback: SecureRandom.hex(4) when 10 attempts all collide.
  #
  # Usage:
  #   handle = Pito::HandleGenerator.call(conversation)
  #   # → "gamma-5912"
  module HandleGenerator
    GREEK_WORDS = %w[
      alpha beta gamma delta epsilon zeta eta theta
      iota kappa lambda mu nu xi omicron pi rho sigma
      tau upsilon phi chi psi omega
    ].freeze

    module_function

    def call(conversation)
      10.times do
        candidate = "#{GREEK_WORDS.sample}-#{rand(1000..9999)}"
        next if taken?(conversation, candidate)
        return candidate
      end
      SecureRandom.hex(4)
    end

    # Returns true when the candidate is already in use in this conversation
    # as a `reply_handle` (any kind, any state including consumed).
    def taken?(conversation, candidate)
      conversation.events
        .where("payload->>'reply_handle' = ?", candidate)
        .exists?
    end
  end
end
