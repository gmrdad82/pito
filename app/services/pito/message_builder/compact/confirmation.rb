# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Compact
      # Builds the confirmation payload for `/compact`.
      # The executor receives this payload when the owner confirms via
      # `#<handle> confirm`, and enqueues CompactJob.
      module Confirmation
        module_function

        # @param conversation [Conversation]
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(conversation:)
          payload = {
            "command"         => "compact",
            "body"            => Pito::Copy.render("pito.copy.compact.confirmation_body"),
            "html"            => true,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
