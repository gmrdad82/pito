# frozen_string_literal: true

module Pito
  # Generates a short, human-readable handle like "alpha-1322" for use in
  # confirmation events. The handle must be unique within a conversation so that
  # `#alpha-1322 confirm` unambiguously identifies one pending prompt.
  #
  # Extensible: any handler that emits a `confirmation` event uses this to
  # populate `confirmation_handle` in the payload.
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
        next if conversation.events
          .where(kind: "confirmation")
          .where("payload->>'confirmation_handle' = ?", candidate)
          .exists?
        return candidate
      end
      SecureRandom.hex(4)
    end
  end
end
